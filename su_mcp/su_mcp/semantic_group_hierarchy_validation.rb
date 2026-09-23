# frozen_string_literal: true

module SU_MCP
  class Server
    unless private_method_defined?(:validate_model_without_group_hierarchy)
      alias_method :validate_model_without_group_hierarchy, :validate_model
      private :validate_model_without_group_hierarchy
    end

    private

    def validate_model(params)
      result = validate_model_without_group_hierarchy(params)
      model = Sketchup.active_model
      errors = result[:errors] || []
      warnings = result[:warnings] || []
      groups = parse_model_semantic_array(model, 'entity_groups_json')

      id_index = {}
      legacy_count = 0
      parent_counts = Hash.new(0)
      child_link_count = 0

      groups.each do |group|
        name = group['name'].to_s.strip
        group_id = group['group_id'].to_s.strip
        child_ids = group['child_group_ids']

        if group_id.empty?
          legacy_count += 1
          unless Array(child_ids).empty?
            errors << "Entity group #{name.inspect} has child groups but no stable group_id."
          end
          next
        end

        if id_index.key?(group_id)
          errors << "Duplicate entity group id #{group_id.inspect}."
        else
          id_index[group_id] = group
        end

        unless child_ids.nil? || child_ids.is_a?(Array)
          errors << "Entity group #{name.inspect} has invalid child_group_ids."
          next
        end

        seen_children = {}
        Array(child_ids).each do |raw_child_id|
          child_id = raw_child_id.to_s.strip
          if child_id.empty?
            errors << "Entity group #{name.inspect} contains a blank child group id."
            next
          end
          if seen_children[child_id]
            errors << "Entity group #{name.inspect} contains duplicate child group id #{child_id.inspect}."
            next
          end
          seen_children[child_id] = true
          child_link_count += 1

          if child_id == group_id
            errors << "Entity group #{name.inspect} cannot be its own child."
          end
        end

        if Array(child_ids).length > ENTITY_GROUP_CHILD_LIMIT
          errors << "Entity group #{name.inspect} exceeds #{ENTITY_GROUP_CHILD_LIMIT} child groups."
        end
      end

      groups.each do |group|
        parent_id = group['group_id'].to_s.strip
        next if parent_id.empty?

        Array(group['child_group_ids']).each do |raw_child_id|
          child_id = raw_child_id.to_s.strip
          next if child_id.empty?
          unless id_index.key?(child_id)
            errors << "Entity group #{group['name'].to_s.inspect} references missing child group id #{child_id.inspect}."
            next
          end
          parent_counts[child_id] += 1
        end
      end

      parent_counts.each do |child_id, count|
        next unless count > 1
        child = id_index[child_id]
        child_name = child ? child['name'].to_s : child_id
        errors << "Entity group #{child_name.inspect} has #{count} parents; group hierarchy must be a tree."
      end

      cycle_messages = hierarchy_cycle_messages(groups, id_index)
      errors.concat(cycle_messages)

      max_depth = hierarchy_validated_max_depth(groups, id_index, errors)
      root_count = groups.count do |group|
        group_id = group['group_id'].to_s.strip
        group_id.empty? || parent_counts[group_id].zero?
      end

      warnings << "#{legacy_count} legacy entity group(s) have no group_id yet; the first hierarchy mutation will migrate them." if legacy_count.positive?

      result[:errors] = errors
      result[:warnings] = warnings
      result[:valid] = errors.empty?
      result[:summary] ||= {}
      result[:summary][:entity_group_parent_links] = child_link_count
      result[:summary][:entity_group_roots] = root_count
      result[:summary][:entity_group_max_depth] = max_depth
      result[:summary][:legacy_entity_groups] = legacy_count
      result
    end

    def hierarchy_cycle_messages(groups, id_index)
      messages = []
      state = {}
      stack = []

      visit = lambda do |group|
        group_id = group['group_id'].to_s.strip
        return if group_id.empty?
        return if state[group_id] == :done

        if state[group_id] == :visiting
          cycle_start = stack.index(group_id) || 0
          cycle_ids = stack[cycle_start..] + [group_id]
          cycle_names = cycle_ids.map do |id|
            item = id_index[id]
            item ? item['name'].to_s : id
          end
          messages << "Entity group hierarchy cycle detected: #{cycle_names.join(' -> ')}."
          return
        end

        state[group_id] = :visiting
        stack << group_id
        Array(group['child_group_ids']).each do |child_id|
          child = id_index[child_id.to_s]
          visit.call(child) if child
        end
        stack.pop
        state[group_id] = :done
      end

      groups.each { |group| visit.call(group) }
      messages.uniq
    end

    def hierarchy_validated_max_depth(groups, id_index, errors)
      parent_ids = {}
      groups.each do |group|
        Array(group['child_group_ids']).each { |child_id| parent_ids[child_id.to_s] = true }
      end
      roots = groups.select do |group|
        group_id = group['group_id'].to_s.strip
        group_id.empty? || !parent_ids[group_id]
      end

      max_depth = 0
      walk = lambda do |group, depth, visiting|
        max_depth = [max_depth, depth].max
        if depth > ENTITY_GROUP_MAX_DEPTH
          errors << "Entity group hierarchy exceeds maximum depth #{ENTITY_GROUP_MAX_DEPTH} at #{group['name'].to_s.inspect}."
          return
        end

        group_id = group['group_id'].to_s.strip
        return if !group_id.empty? && visiting[group_id]
        next_visiting = visiting.dup
        next_visiting[group_id] = true unless group_id.empty?

        Array(group['child_group_ids']).each do |child_id|
          child = id_index[child_id.to_s]
          walk.call(child, depth + 1, next_visiting) if child
        end
      end

      roots.each { |root| walk.call(root, 0, {}) }
      max_depth
    end
  end
end

# frozen_string_literal: true

require 'json'
require 'securerandom'

module SU_MCP
  class Server
    GROUP_HIERARCHY_TOOL_NAMES = %w[
      add_child_entity_group
      remove_child_entity_group
      move_entity_group
      inspect_entity_group_tree
      list_entity_group_roots
    ].freeze unless const_defined?(:GROUP_HIERARCHY_TOOL_NAMES, false)

    ENTITY_GROUP_CHILD_LIMIT = 200 unless const_defined?(:ENTITY_GROUP_CHILD_LIMIT, false)
    ENTITY_GROUP_MAX_DEPTH = 32 unless const_defined?(:ENTITY_GROUP_MAX_DEPTH, false)

    unless private_method_defined?(:handle_tool_call_without_group_hierarchy)
      alias_method :handle_tool_call_without_group_hierarchy, :handle_tool_call
      private :handle_tool_call_without_group_hierarchy
    end

    unless private_method_defined?(:inspect_model_without_group_hierarchy)
      alias_method :inspect_model_without_group_hierarchy, :inspect_model
      private :inspect_model_without_group_hierarchy
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_group_hierarchy(request) unless GROUP_HIERARCHY_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'add_child_entity_group' then add_child_entity_group(args)
        when 'remove_child_entity_group' then remove_child_entity_group(args)
        when 'move_entity_group' then move_entity_group(args)
        when 'inspect_entity_group_tree' then inspect_entity_group_tree(args)
        when 'list_entity_group_roots' then list_entity_group_roots(args)
        else raise "Unknown entity group hierarchy tool: #{tool_name}"
        end
      end
    end

    def inspect_model(params)
      result = inspect_model_without_group_hierarchy(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      ids = hierarchy_group_index(groups)
      roots = hierarchy_root_groups(groups)
      result[:entity_groups] = groups.map { |group| entity_group_result(model, group) }
      result[:entity_group_roots] = roots.map { |group| group['name'].to_s }
      result[:semantic_summary] ||= {}
      result[:semantic_summary][:entity_group_parent_links] = groups.sum { |group| Array(group['child_group_ids']).length }
      result[:semantic_summary][:entity_group_roots] = roots.length
      result[:semantic_summary][:entity_group_max_depth] = hierarchy_max_depth(groups, ids)
      result
    end

    # v1.15 group creation supports entity members, child groups, or both.
    def create_entity_group(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      name = normalized_name(params['name'])
      raise 'name is required.' unless name
      groups = entity_groups(model)
      ensure_entity_group_name_available!(model, groups, name)

      members = resolve_optional_group_entity_ids(model, params['entity_ids'])
      child_names = normalized_group_name_list(params['child_group_names'])
      raise 'Provide at least one entity member or child group.' if members.empty? && child_names.empty?

      model.start_operation('OpenSU: Create Entity Group', true)
      begin
        ensure_group_ids!(groups)
        child_groups = child_names.map { |child_name| find_entity_group!(groups, child_name) }
        ensure_children_available_for_parent!(groups, child_groups, nil)

        group = {
          'group_id' => next_entity_group_id(groups),
          'name' => name,
          'member_persistent_ids' => members.map { |entity| persistent_member_id(entity) },
          'child_group_ids' => child_groups.map { |child| child['group_id'] },
          'description' => normalized_name(params['description']),
          'source_ref' => normalized_name(params['source_ref'])
        }.compact

        groups << group
        sort_entity_groups!(groups)
        persist_entity_groups!(model, groups)
        model.commit_operation
        return entity_group_result(model, group)
      rescue StandardError
        model.abort_operation
        raise
      end
    end

    # A parent with children may legitimately have zero direct entity members.
    def remove_entities_from_group(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      removals = resolve_group_entity_ids(model, params['entity_ids'])
      ids = Array(group['member_persistent_ids']).map(&:to_i)
      removal_ids = removals.map { |entity| persistent_member_id(entity) }
      missing = removal_ids - ids
      raise "Entities are not members of group #{group['name'].inspect}: #{missing.join(', ')}." unless missing.empty?

      remaining = ids - removal_ids
      if remaining.empty? && Array(group['child_group_ids']).empty?
        raise 'Removing these members would leave the group empty; dissolve the group instead.'
      end

      model.start_operation('OpenSU: Remove Group Members', true)
      begin
        group['member_persistent_ids'] = remaining
        persist_entity_groups!(model, groups)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group)
    end

    def prune_missing_entity_group_members(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      ids = Array(group['member_persistent_ids']).map(&:to_i)
      live_ids = ids.select { |persistent_id| find_root_entity_by_persistent_id(model, persistent_id) }
      missing_ids = ids - live_ids

      return entity_group_result(model, group).merge(pruned_count: 0, pruned_persistent_ids: []) if missing_ids.empty?
      if live_ids.empty? && Array(group['child_group_ids']).empty?
        raise 'All group members are missing and the group has no child groups; dissolve the group instead.'
      end

      model.start_operation('OpenSU: Prune Missing Group Members', true)
      begin
        group['member_persistent_ids'] = live_ids
        persist_entity_groups!(model, groups)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group).merge(
        pruned_count: missing_ids.length,
        pruned_persistent_ids: missing_ids
      )
    end

    # Dissolving a node never deletes child groups or geometry.
    # Children are promoted to the dissolved node's parent, or become roots.
    def delete_entity_group(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      snapshot = entity_group_result(model, group)

      model.start_operation('OpenSU: Dissolve Entity Group', true)
      begin
        ensure_group_ids!(groups)
        group_id = group['group_id']
        parent = hierarchy_parent_group(groups, group_id)
        children = Array(group['child_group_ids'])

        if parent
          parent_children = Array(parent['child_group_ids']).reject { |child_id| child_id == group_id }
          parent['child_group_ids'] = (parent_children + children).uniq
        end

        groups.each do |candidate|
          next if parent && candidate.equal?(parent)
          candidate['child_group_ids'] = Array(candidate['child_group_ids']).reject { |child_id| child_id == group_id }
        end

        groups.delete(group)
        persist_entity_groups!(model, groups)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        deleted: true,
        members_deleted: false,
        child_groups_deleted: false,
        children_promoted: true,
        group: snapshot
      }
    end

    def add_child_entity_group(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      parent = find_entity_group!(groups, params['parent_group_name'])
      child = find_entity_group!(groups, params['child_group_name'])
      raise 'A group cannot be its own child.' if parent.equal?(child)

      model.start_operation('OpenSU: Nest Entity Group', true)
      begin
        ensure_group_ids!(groups)
        ensure_child_can_attach!(groups, parent, child)
        children = Array(parent['child_group_ids'])
        parent['child_group_ids'] = children + [child['group_id']]
        persist_entity_groups!(model, groups)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, parent)
    end

    def remove_child_entity_group(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      parent = find_entity_group!(groups, params['parent_group_name'])
      child = find_entity_group!(groups, params['child_group_name'])

      model.start_operation('OpenSU: Unnest Entity Group', true)
      begin
        ensure_group_ids!(groups)
        child_id = child['group_id']
        current = Array(parent['child_group_ids'])
        raise "Group #{child['name'].inspect} is not a child of #{parent['name'].inspect}." unless current.include?(child_id)
        parent['child_group_ids'] = current.reject { |value| value == child_id }
        persist_entity_groups!(model, groups)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        parent: entity_group_result(model, parent),
        detached_child: entity_group_result(model, child)
      }
    end

    def move_entity_group(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      to_root = boolean_value(params['to_root'] || false, 'to_root')
      new_parent_name = normalized_name(params['new_parent_group_name'])
      raise 'Provide new_parent_group_name or to_root=true.' if !to_root && !new_parent_name
      raise 'Choose either new_parent_group_name or to_root=true, not both.' if to_root && new_parent_name

      model.start_operation('OpenSU: Move Entity Group', true)
      begin
        ensure_group_ids!(groups)
        group_id = group['group_id']
        old_parent = hierarchy_parent_group(groups, group_id)

        new_parent = new_parent_name ? find_entity_group!(groups, new_parent_name) : nil
        raise 'A group cannot be its own parent.' if new_parent && new_parent.equal?(group)
        ensure_child_can_attach!(groups, new_parent, group, allow_existing_parent: true) if new_parent

        if old_parent
          old_parent['child_group_ids'] = Array(old_parent['child_group_ids']).reject { |value| value == group_id }
        end
        if new_parent
          new_parent['child_group_ids'] = (Array(new_parent['child_group_ids']) + [group_id]).uniq
        end

        persist_entity_groups!(model, groups)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        group: entity_group_result(model, group),
        parent: new_parent ? entity_group_result(model, new_parent, include_members: false) : nil
      }
    end

    def inspect_entity_group_tree(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      depth_limit = integer_in_range(params['max_depth'] || ENTITY_GROUP_MAX_DEPTH, 'max_depth', 1, ENTITY_GROUP_MAX_DEPTH)
      tree = entity_group_tree_result(model, groups, group, 0, depth_limit, {})
      recursive_members = resolve_entity_group_tree_members!(model, groups, group)
      {
        type: 'entity_group_tree',
        root: tree,
        recursive_member_count: recursive_members.length,
        recursive_members: recursive_members.map { |entity| edit_entity_result(entity) }
      }
    end

    def list_entity_group_roots(_params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      roots = hierarchy_root_groups(groups)
      {
        count: roots.length,
        roots: roots.map { |group| entity_group_result(model, group, include_members: false) }
      }
    end

    # Parent operations recurse through all descendants and deduplicate shared entities.
    def set_entity_group_visibility(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      members = resolve_entity_group_tree_members!(model, groups, group)
      visible = boolean_value(params['visible'], 'visible')

      model.start_operation('OpenSU: Set Entity Group Tree Visibility', true)
      begin
        members.each { |entity| entity.visible = visible }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group).merge(visible: visible, affected_entity_count: members.length)
    end

    def set_entity_group_tag(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      members = resolve_entity_group_tree_members!(model, groups, group)
      tag_name = normalized_name(params['tag_name'])
      raise 'tag_name is required.' unless tag_name

      model.start_operation('OpenSU: Set Entity Group Tree Tag', true)
      begin
        tag = model.layers[tag_name] || model.layers.add(tag_name)
        members.each { |entity| entity.layer = tag }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group).merge(tag_name: tag_name, affected_entity_count: members.length)
    end

    def transform_entity_group(params)
      model = Sketchup.active_model
      groups_data = entity_groups(model)
      group = find_entity_group!(groups_data, params['group_name'])
      members = resolve_entity_group_tree_members!(model, groups_data, group)
      transformable = require_transformable_group_members!(members)

      translation_mm = vector3_numbers(params['translation_mm'] || [0, 0, 0], 'translation_mm')
      rotation_deg = finite_number(params.key?('rotation_z_deg') ? params['rotation_z_deg'] : 0, 'rotation_z_deg')
      raise 'Transform must move or rotate the entity group.' if translation_mm.all? { |v| v.abs < 0.000001 } && rotation_deg.abs < 0.000001
      pivot_mm = params['pivot_mm'] ? vector3_numbers(params['pivot_mm'], 'pivot_mm') : entity_group_bounds_center_mm(transformable)
      transform = semantic_edit_transformation(translation_mm, rotation_deg, pivot_mm)

      model.start_operation('OpenSU: Transform Entity Group Tree', true)
      begin
        transformable.each do |entity|
          children = entity.entities.to_a
          entity.entities.transform_entities(transform, children) unless children.empty?
          transform_semantic_metadata!(entity, translation_mm, rotation_deg, pivot_mm)
          entity.set_attribute('OpenSU', 'last_edit', 'group_tree_transform')
        end
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group).merge(
        affected_entity_count: transformable.length,
        translation_mm: translation_mm,
        rotation_z_deg: rotation_deg,
        pivot_mm: pivot_mm
      )
    end

    # Duplicate an entire group subtree, preserving hierarchy and shared memberships.
    def duplicate_entity_group(params)
      model = Sketchup.active_model
      groups_data = entity_groups(model)
      source_root = find_entity_group!(groups_data, params['group_name'])
      ensure_group_ids!(groups_data)
      subtree = hierarchy_subtree_groups(groups_data, source_root)
      source_entities = resolve_groups_direct_members_unique!(model, subtree)
      transformable = require_transformable_group_members!(source_entities)

      new_root_name = normalized_name(params['new_group_name']) ||
                      next_entity_group_name(model, groups_data, "#{source_root['name']}_Copy")
      ensure_entity_group_name_available!(model, groups_data, new_root_name)

      translation_mm = vector3_numbers(params['translation_mm'] || [0, 0, 0], 'translation_mm')
      rotation_deg = finite_number(params.key?('rotation_z_deg') ? params['rotation_z_deg'] : 0, 'rotation_z_deg')
      pivot_mm = params['pivot_mm'] ? vector3_numbers(params['pivot_mm'], 'pivot_mm') : entity_group_bounds_center_mm(transformable)
      transform = semantic_edit_transformation(translation_mm, rotation_deg, pivot_mm)

      copied_entities = {}
      new_groups_by_old_id = {}

      model.start_operation('OpenSU: Duplicate Entity Group Tree', true)
      begin
        transformable.each do |source|
          copy = source.copy
          copy.name = next_group_copy_entity_name(model, source.name.to_s)
          if translation_mm.any? { |v| v.abs >= 0.000001 } || rotation_deg.abs >= 0.000001
            children = copy.entities.to_a
            copy.entities.transform_entities(transform, children) unless children.empty?
            transform_semantic_metadata!(copy, translation_mm, rotation_deg, pivot_mm)
          end
          copy.set_attribute('OpenSU', 'duplicated_from', source.name.to_s)
          copied_entities[persistent_member_id(source)] = copy
        end

        subtree.each do |source_group|
          old_id = source_group['group_id']
          group_name = if source_group.equal?(source_root)
                         new_root_name
                       else
                         next_entity_group_name(model, groups_data + new_groups_by_old_id.values, "#{source_group['name']}_Copy")
                       end
          new_groups_by_old_id[old_id] = {
            'group_id' => next_entity_group_id(groups_data + new_groups_by_old_id.values),
            'name' => group_name,
            'member_persistent_ids' => Array(source_group['member_persistent_ids']).map do |pid|
              persistent_member_id(copied_entities.fetch(pid.to_i))
            end,
            'child_group_ids' => [],
            'description' => source_group['description'],
            'source_ref' => source_group['source_ref']
          }.compact
        end

        subtree.each do |source_group|
          copy_group = new_groups_by_old_id.fetch(source_group['group_id'])
          copy_group['child_group_ids'] = Array(source_group['child_group_ids']).filter_map do |child_id|
            child_copy = new_groups_by_old_id[child_id]
            child_copy && child_copy['group_id']
          end
        end

        copied_root = new_groups_by_old_id.fetch(source_root['group_id'])
        copied_root['description'] = normalized_name(params['description']) if params['description']
        copied_root['source_ref'] = normalized_name(params['source_ref']) if params['source_ref']

        groups_data.concat(new_groups_by_old_id.values)
        sort_entity_groups!(groups_data)
        persist_entity_groups!(model, groups_data)
        model.commit_operation

        return entity_group_result(model, copied_root).merge(
          duplicated_from_group: source_root['name'].to_s,
          created_group_count: new_groups_by_old_id.length,
          created_entity_count: copied_entities.length,
          translation_mm: translation_mm,
          rotation_z_deg: rotation_deg,
          pivot_mm: pivot_mm
        )
      rescue StandardError
        model.abort_operation
        raise
      end
    end

    def entity_group_result(model, group, include_members: true)
      groups = entity_groups(model)
      ids = Array(group['member_persistent_ids']).map(&:to_i)
      members = []
      missing = []
      ids.each do |persistent_id|
        entity = find_root_entity_by_persistent_id(model, persistent_id)
        if entity
          members << entity
        else
          missing << persistent_id
        end
      end

      group_id = group['group_id']
      child_ids = Array(group['child_group_ids'])
      children = child_ids.filter_map { |child_id| hierarchy_group_index(groups)[child_id] }
      missing_child_ids = child_ids.reject { |child_id| hierarchy_group_index(groups).key?(child_id) }
      parent = group_id ? hierarchy_parent_group(groups, group_id) : nil

      recursive_count = begin
        group_id ? resolve_entity_group_tree_members!(model, groups, group).length : members.length
      rescue StandardError
        members.length
      end

      result = {
        type: 'entity_group',
        group_id: group_id,
        name: group['name'].to_s,
        description: group['description'],
        source_ref: group['source_ref'],
        parent_group: parent && parent['name'].to_s,
        child_group_count: child_ids.length,
        child_groups: children.map { |child| child['name'].to_s },
        missing_child_group_ids: missing_child_ids,
        member_count: ids.length,
        recursive_member_count: recursive_count,
        missing_member_count: missing.length,
        missing_persistent_ids: missing
      }.compact
      result[:members] = members.map { |entity| edit_entity_result(entity) } if include_members
      result
    end

    def resolve_optional_group_entity_ids(model, raw_ids)
      return [] if raw_ids.nil? || (raw_ids.is_a?(Array) && raw_ids.empty?)
      resolve_group_entity_ids(model, raw_ids)
    end

    def normalized_group_name_list(raw_names)
      return [] if raw_names.nil?
      raise 'child_group_names must be an array.' unless raw_names.is_a?(Array)
      names = raw_names.map { |value| normalized_name(value) }
      raise 'child_group_names cannot contain blank names.' if names.any?(&:nil?)
      raise 'Duplicate child group name.' if names.map(&:downcase).uniq.length != names.length
      raise "A group may contain at most #{ENTITY_GROUP_CHILD_LIMIT} child groups." if names.length > ENTITY_GROUP_CHILD_LIMIT
      names
    end

    def next_entity_group_id(groups)
      existing = groups.map { |group| group['group_id'].to_s }.reject(&:empty?)
      loop do
        candidate = SecureRandom.uuid
        return candidate unless existing.include?(candidate)
      end
    end

    def ensure_group_ids!(groups)
      seen = {}
      groups.each do |group|
        group_id = group['group_id'].to_s.strip
        if group_id.empty? || seen[group_id]
          group_id = next_entity_group_id(groups)
          group['group_id'] = group_id
        end
        seen[group_id] = true
        group['child_group_ids'] = Array(group['child_group_ids']).map(&:to_s).reject(&:empty?).uniq
      end
    end

    def hierarchy_group_index(groups)
      groups.each_with_object({}) do |group, index|
        group_id = group['group_id'].to_s
        index[group_id] = group unless group_id.empty?
      end
    end

    def hierarchy_parent_group(groups, child_id)
      groups.find { |candidate| Array(candidate['child_group_ids']).include?(child_id) }
    end

    def hierarchy_root_groups(groups)
      child_ids = groups.flat_map { |group| Array(group['child_group_ids']) }.uniq
      groups.reject do |group|
        group_id = group['group_id'].to_s
        !group_id.empty? && child_ids.include?(group_id)
      end
    end

    def hierarchy_subtree_groups(groups, root)
      index = hierarchy_group_index(groups)
      result = []
      visiting = {}
      visit = lambda do |group, depth|
        raise "Entity group hierarchy exceeds #{ENTITY_GROUP_MAX_DEPTH} levels." if depth > ENTITY_GROUP_MAX_DEPTH
        group_id = group['group_id'].to_s
        raise "Cycle detected at group #{group['name'].inspect}." if visiting[group_id]
        visiting[group_id] = true
        result << group
        Array(group['child_group_ids']).each do |child_id|
          child = index[child_id]
          raise "Group #{group['name'].inspect} references missing child group id #{child_id}." unless child
          visit.call(child, depth + 1)
        end
        visiting.delete(group_id)
      end
      visit.call(root, 0)
      result
    end

    def hierarchy_descendant_ids(groups, root)
      hierarchy_subtree_groups(groups, root).drop(1).map { |group| group['group_id'] }
    end

    def hierarchy_max_depth(groups, index = hierarchy_group_index(groups))
      max_depth = 0
      hierarchy_root_groups(groups).each do |root|
        walk = lambda do |group, depth, visiting|
          max_depth = [max_depth, depth].max
          return if depth >= ENTITY_GROUP_MAX_DEPTH
          group_id = group['group_id'].to_s
          return if visiting[group_id]
          next_visiting = visiting.merge(group_id => true)
          Array(group['child_group_ids']).each do |child_id|
            child = index[child_id]
            walk.call(child, depth + 1, next_visiting) if child
          end
        end
        walk.call(root, 0, {})
      end
      max_depth
    end

    def ensure_children_available_for_parent!(groups, child_groups, parent)
      child_groups.each do |child|
        existing_parent = hierarchy_parent_group(groups, child['group_id'])
        if existing_parent && (!parent || !existing_parent.equal?(parent))
          raise "Child group #{child['name'].inspect} already belongs to parent #{existing_parent['name'].inspect}."
        end
      end
    end

    def ensure_child_can_attach!(groups, parent, child, allow_existing_parent: false)
      raise 'parent group is required.' unless parent
      existing_parent = hierarchy_parent_group(groups, child['group_id'])
      if existing_parent && !allow_existing_parent && !existing_parent.equal?(parent)
        raise "Child group #{child['name'].inspect} already belongs to parent #{existing_parent['name'].inspect}."
      end
      if existing_parent && existing_parent.equal?(parent)
        raise "Group #{child['name'].inspect} is already a child of #{parent['name'].inspect}."
      end
      descendants = hierarchy_descendant_ids(groups, child)
      if descendants.include?(parent['group_id'])
        raise "Cannot nest #{child['name'].inspect} under #{parent['name'].inspect}; that would create a cycle."
      end
      if Array(parent['child_group_ids']).length >= ENTITY_GROUP_CHILD_LIMIT
        raise "Parent group may contain at most #{ENTITY_GROUP_CHILD_LIMIT} child groups."
      end
    end

    def resolve_entity_group_tree_members!(model, groups, root)
      subtree = hierarchy_subtree_groups(groups, root)
      resolve_groups_direct_members_unique!(model, subtree)
    end

    def resolve_groups_direct_members_unique!(model, groups)
      members_by_pid = {}
      missing = []
      groups.each do |group|
        Array(group['member_persistent_ids']).each do |raw_pid|
          pid = raw_pid.to_i
          next if members_by_pid.key?(pid)
          entity = find_root_entity_by_persistent_id(model, pid)
          if entity
            members_by_pid[pid] = entity
          else
            missing << "#{group['name']}:#{pid}"
          end
        end
      end
      raise "Entity group tree contains missing members: #{missing.join(', ')}." unless missing.empty?
      members_by_pid.values
    end

    def entity_group_tree_result(model, groups, group, depth, depth_limit, visiting)
      raise "Tree inspection exceeded max_depth=#{depth_limit}." if depth > depth_limit
      group_id = group['group_id'].to_s
      raise "Cycle detected at group #{group['name'].inspect}." if visiting[group_id]
      next_visiting = visiting.merge(group_id => true)
      index = hierarchy_group_index(groups)
      direct = entity_group_result(model, group)
      direct[:depth] = depth
      direct[:children] = Array(group['child_group_ids']).map do |child_id|
        child = index[child_id]
        if child
          entity_group_tree_result(model, groups, child, depth + 1, depth_limit, next_visiting)
        else
          { type: 'missing_entity_group', group_id: child_id }
        end
      end
      direct
    end
  end
end

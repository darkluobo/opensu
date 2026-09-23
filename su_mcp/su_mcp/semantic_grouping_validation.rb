# frozen_string_literal: true

module SU_MCP
  class Server
    unless private_method_defined?(:validate_model_without_entity_grouping)
      alias_method :validate_model_without_entity_grouping, :validate_model
      private :validate_model_without_entity_grouping
    end

    private

    def validate_model(params)
      result = validate_model_without_entity_grouping(params)
      model = Sketchup.active_model
      errors = result[:errors] || []
      warnings = result[:warnings] || []
      groups = parse_model_semantic_array(model, 'entity_groups_json')

      names = {}
      membership_count = 0

      groups.each_with_index do |group, index|
        name = group['name'].to_s.strip
        errors << "Entity group ##{index + 1} has no name." if name.empty?

        key = name.downcase
        errors << "Duplicate entity group name #{name.inspect}." if names.key?(key)
        names[key] = true

        root_conflict = editable_root_entities(model).any? { |entity| entity.name.to_s.casecmp?(name) }
        warnings << "Entity group #{name.inspect} has the same name as a root entity." if !name.empty? && root_conflict

        ids = group['member_persistent_ids']
        unless ids.is_a?(Array) && !ids.empty?
          errors << "Entity group #{name.inspect} must contain at least one member."
          next
        end

        if ids.length > ENTITY_GROUP_MEMBER_LIMIT
          errors << "Entity group #{name.inspect} exceeds #{ENTITY_GROUP_MEMBER_LIMIT} members."
        end

        seen = {}
        ids.each do |raw_id|
          unless raw_id.is_a?(Numeric) && raw_id.to_i.positive?
            errors << "Entity group #{name.inspect} has invalid member persistent id #{raw_id.inspect}."
            next
          end

          persistent_id = raw_id.to_i
          if seen[persistent_id]
            errors << "Entity group #{name.inspect} contains duplicate member persistent id #{persistent_id}."
            next
          end
          seen[persistent_id] = true
          membership_count += 1

          entity = find_root_entity_by_persistent_id(model, persistent_id)
          unless entity
            errors << "Entity group #{name.inspect} references missing member persistent id #{persistent_id}."
            next
          end
          if entity.get_attribute('OpenSU', 'type').to_s.empty?
            errors << "Entity group #{name.inspect} member #{entity.name.to_s.inspect} is not an OpenSU semantic entity."
          end
        end
      end

      result[:errors] = errors
      result[:warnings] = warnings
      result[:valid] = errors.empty?
      result[:summary] ||= {}
      result[:summary][:entity_groups] = groups.length
      result[:summary][:entity_group_memberships] = membership_count
      result
    end
  end
end

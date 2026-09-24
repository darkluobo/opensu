# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    ENTITY_GROUP_TOOL_NAMES = %w[
      create_entity_group
      add_entities_to_group
      remove_entities_from_group
      prune_missing_entity_group_members
      rename_entity_group
      delete_entity_group
      list_entity_groups
      inspect_entity_group
      set_entity_group_visibility
      set_entity_group_tag
      transform_entity_group
      duplicate_entity_group
    ].freeze unless const_defined?(:ENTITY_GROUP_TOOL_NAMES, false)

    ENTITY_GROUP_MEMBER_LIMIT = 500 unless const_defined?(:ENTITY_GROUP_MEMBER_LIMIT, false)

    unless private_method_defined?(:handle_tool_call_without_entity_grouping)
      alias_method :handle_tool_call_without_entity_grouping, :handle_tool_call
      private :handle_tool_call_without_entity_grouping
    end

    unless private_method_defined?(:inspect_model_without_entity_grouping)
      alias_method :inspect_model_without_entity_grouping, :inspect_model
      private :inspect_model_without_entity_grouping
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_entity_grouping(request) unless ENTITY_GROUP_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'create_entity_group' then create_entity_group(args)
        when 'add_entities_to_group' then add_entities_to_group(args)
        when 'remove_entities_from_group' then remove_entities_from_group(args)
        when 'prune_missing_entity_group_members' then prune_missing_entity_group_members(args)
        when 'rename_entity_group' then rename_entity_group(args)
        when 'delete_entity_group' then delete_entity_group(args)
        when 'list_entity_groups' then list_entity_groups(args)
        when 'inspect_entity_group' then inspect_entity_group(args)
        when 'set_entity_group_visibility' then set_entity_group_visibility(args)
        when 'set_entity_group_tag' then set_entity_group_tag(args)
        when 'transform_entity_group' then transform_entity_group(args)
        when 'duplicate_entity_group' then duplicate_entity_group(args)
        else raise "Unknown entity grouping tool: #{tool_name}"
        end
      end
    end

    def inspect_model(params)
      result = inspect_model_without_entity_grouping(params)
      model = Sketchup.active_model
      groups = parse_model_semantic_array(model, 'entity_groups_json')
      result[:entity_groups] = groups.map { |group| entity_group_result(model, group) }
      result[:semantic_summary] ||= {}
      result[:semantic_summary][:entity_groups] = groups.length
      result[:semantic_summary][:entity_group_memberships] = groups.sum do |group|
        Array(group['member_persistent_ids']).length
      end
      result
    end

    def create_entity_group(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      name = normalized_name(params['name'])
      raise 'name is required.' unless name
      groups = entity_groups(model)
      ensure_entity_group_name_available!(model, groups, name)

      members = resolve_group_entity_ids(model, params['entity_ids'])
      description = normalized_name(params['description'])
      source_ref = normalized_name(params['source_ref'])
      group = {
        name: name,
        member_persistent_ids: members.map { |entity| persistent_member_id(entity) },
        description: description,
        source_ref: source_ref
      }.compact

      model.start_operation('OpenSU: Create Entity Group', true)
      begin
        groups << JSON.parse(JSON.generate(group))
        sort_entity_groups!(groups)
        persist_entity_groups!(model, groups)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, JSON.parse(JSON.generate(group)))
    end

    def add_entities_to_group(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      additions = resolve_group_entity_ids(model, params['entity_ids'])
      ids = Array(group['member_persistent_ids']).map(&:to_i)
      addition_ids = additions.map { |entity| persistent_member_id(entity) }
      duplicate_ids = addition_ids & ids
      raise "Entities are already members of group #{group['name'].inspect}: #{duplicate_ids.join(', ')}." unless duplicate_ids.empty?

      merged = ids + addition_ids
      raise "An entity group may contain at most #{ENTITY_GROUP_MEMBER_LIMIT} members." if merged.length > ENTITY_GROUP_MEMBER_LIMIT

      model.start_operation('OpenSU: Add Group Members', true)
      begin
        group['member_persistent_ids'] = merged
        persist_entity_groups!(model, groups)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group)
    end

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
      raise 'Removing these members would leave the group empty; dissolve the group instead.' if remaining.empty?

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
      raise 'All group members are missing; dissolve the group instead.' if live_ids.empty?

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

    def rename_entity_group(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      new_name = normalized_name(params['new_name'])
      raise 'new_name is required.' unless new_name
      ensure_entity_group_name_available!(model, groups, new_name, group)
      old_name = group['name'].to_s

      model.start_operation('OpenSU: Rename Entity Group', true)
      begin
        group['name'] = new_name
        sort_entity_groups!(groups)
        persist_entity_groups!(model, groups)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group).merge(old_name: old_name)
    end

    def delete_entity_group(params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      group = find_entity_group!(groups, params['group_name'])
      snapshot = entity_group_result(model, group)

      model.start_operation('OpenSU: Dissolve Entity Group', true)
      begin
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
        group: snapshot
      }
    end

    def list_entity_groups(_params)
      model = Sketchup.active_model
      groups = entity_groups(model)
      {
        count: groups.length,
        groups: groups.map { |group| entity_group_result(model, group, include_members: false) }
      }
    end

    def inspect_entity_group(params)
      model = Sketchup.active_model
      group = find_entity_group!(entity_groups(model), params['group_name'])
      entity_group_result(model, group)
    end

    def set_entity_group_visibility(params)
      model = Sketchup.active_model
      group = find_entity_group!(entity_groups(model), params['group_name'])
      members = resolve_entity_group_members!(model, group)
      visible = boolean_value(params['visible'], 'visible')

      model.start_operation('OpenSU: Set Entity Group Visibility', true)
      begin
        members.each { |entity| entity.visible = visible }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group).merge(visible: visible)
    end

    def set_entity_group_tag(params)
      model = Sketchup.active_model
      group = find_entity_group!(entity_groups(model), params['group_name'])
      members = resolve_entity_group_members!(model, group)
      tag_name = normalized_name(params['tag_name'])
      raise 'tag_name is required.' unless tag_name

      model.start_operation('OpenSU: Set Entity Group Tag', true)
      begin
        tag = model.layers[tag_name] || model.layers.add(tag_name)
        members.each { |entity| entity.layer = tag }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group).merge(tag_name: tag_name)
    end

    def transform_entity_group(params)
      model = Sketchup.active_model
      group = find_entity_group!(entity_groups(model), params['group_name'])
      members = resolve_entity_group_members!(model, group)
      groups = require_transformable_group_members!(members)

      translation_mm = vector3_numbers(params['translation_mm'] || [0, 0, 0], 'translation_mm')
      rotation_deg = finite_number(params.key?('rotation_z_deg') ? params['rotation_z_deg'] : 0, 'rotation_z_deg')
      raise 'Transform must move or rotate the entity group.' if translation_mm.all? { |v| v.abs < 0.000001 } && rotation_deg.abs < 0.000001
      pivot_mm = params['pivot_mm'] ? vector3_numbers(params['pivot_mm'], 'pivot_mm') : entity_group_bounds_center_mm(groups)

      model.start_operation('OpenSU: Transform Entity Group', true)
      begin
        groups.each do |entity|
          transform = semantic_edit_transformation(translation_mm, rotation_deg, pivot_mm)
          children = entity.entities.to_a
          entity.entities.transform_entities(transform, children) unless children.empty?
          transform_semantic_metadata!(entity, translation_mm, rotation_deg, pivot_mm)
          entity.set_attribute('OpenSU', 'last_edit', 'group_transform')
        end
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      entity_group_result(model, group).merge(
        translation_mm: translation_mm,
        rotation_z_deg: rotation_deg,
        pivot_mm: pivot_mm
      )
    end

    def duplicate_entity_group(params)
      model = Sketchup.active_model
      groups_data = entity_groups(model)
      source_group = find_entity_group!(groups_data, params['group_name'])
      members = resolve_entity_group_members!(model, source_group)
      source_members = require_transformable_group_members!(members)

      new_group_name = normalized_name(params['new_group_name']) || next_entity_group_name(model, groups_data, "#{source_group['name']}_Copy")
      ensure_entity_group_name_available!(model, groups_data, new_group_name)
      translation_mm = vector3_numbers(params['translation_mm'] || [0, 0, 0], 'translation_mm')
      rotation_deg = finite_number(params.key?('rotation_z_deg') ? params['rotation_z_deg'] : 0, 'rotation_z_deg')
      pivot_mm = params['pivot_mm'] ? vector3_numbers(params['pivot_mm'], 'pivot_mm') : entity_group_bounds_center_mm(source_members)

      copies = []
      model.start_operation('OpenSU: Duplicate Entity Group', true)
      begin
        source_members.each do |source|
          copy = source.copy
          copy.name = next_group_copy_entity_name(model, source.name.to_s)
          if translation_mm.any? { |v| v.abs >= 0.000001 } || rotation_deg.abs >= 0.000001
            transform = semantic_edit_transformation(translation_mm, rotation_deg, pivot_mm)
            children = copy.entities.to_a
            copy.entities.transform_entities(transform, children) unless children.empty?
            transform_semantic_metadata!(copy, translation_mm, rotation_deg, pivot_mm)
          end
          copy.set_attribute('OpenSU', 'duplicated_from', source.name.to_s)
          copies << copy
        end

        new_group = {
          'name' => new_group_name,
          'member_persistent_ids' => copies.map { |copy| persistent_member_id(copy) },
          'description' => normalized_name(params['description']) || source_group['description'],
          'source_ref' => normalized_name(params['source_ref']) || source_group['source_ref']
        }.compact
        groups_data << new_group
        sort_entity_groups!(groups_data)
        persist_entity_groups!(model, groups_data)
        model.commit_operation

        return entity_group_result(model, new_group).merge(
          duplicated_from_group: source_group['name'].to_s,
          translation_mm: translation_mm,
          rotation_z_deg: rotation_deg,
          pivot_mm: pivot_mm
        )
      rescue StandardError
        model.abort_operation
        raise
      end
    end

    def entity_groups(model)
      raise 'No active SketchUp model.' unless model
      parse_model_semantic_array(model, 'entity_groups_json')
    end

    def persist_entity_groups!(model, groups)
      model.set_attribute('OpenSU', 'entity_groups_json', JSON.generate(groups))
    end

    def sort_entity_groups!(groups)
      groups.sort_by! { |group| group['name'].to_s.downcase }
    end

    def find_entity_group!(groups, raw_name)
      name = normalized_name(raw_name)
      raise 'group_name is required.' unless name
      matches = groups.select { |group| group['name'].to_s.casecmp?(name) }
      raise "No entity group named #{name.inspect} exists." if matches.empty?
      raise "More than one entity group named #{name.inspect} exists." if matches.length > 1
      matches.first
    end

    def ensure_entity_group_name_available!(model, groups, name, except_group = nil)
      duplicate_group = groups.any? do |group|
        next false if except_group && group.equal?(except_group)
        group['name'].to_s.casecmp?(name)
      end
      raise "An entity group named #{name.inspect} already exists." if duplicate_group

      root_conflict = editable_root_entities(model).any? { |entity| entity.name.to_s.casecmp?(name) }
      raise "A root entity named #{name.inspect} already exists; choose a distinct group name." if root_conflict
    end

    def resolve_group_entity_ids(model, raw_ids)
      raise 'entity_ids must be a non-empty array.' unless raw_ids.is_a?(Array) && !raw_ids.empty?
      raise "An entity group may contain at most #{ENTITY_GROUP_MEMBER_LIMIT} members." if raw_ids.length > ENTITY_GROUP_MEMBER_LIMIT

      seen = {}
      raw_ids.map do |value|
        id = integer_in_range(value, 'entity_id', 1, 2_147_483_647)
        raise "Duplicate entity_id #{id}." if seen[id]
        seen[id] = true
        entity = model.find_entity_by_id(id)
        raise "Entity #{id} was not found." unless entity
        unless editable_root_entities(model).include?(entity)
          raise "Entity #{id} is not a root Group or ComponentInstance."
        end
        raise "Entity #{id} is not an OpenSU semantic entity." if entity.get_attribute('OpenSU', 'type').to_s.empty?
        entity
      end
    end

    def persistent_member_id(entity)
      value = entity.respond_to?(:persistent_id) ? entity.persistent_id : entity.entityID
      value.to_i
    end

    def find_root_entity_by_persistent_id(model, persistent_id)
      entity = nil
      if model.respond_to?(:find_entity_by_persistent_id)
        begin
          entity = model.find_entity_by_persistent_id(persistent_id.to_i)
        rescue StandardError
          entity = nil
        end
      end
      entity ||= editable_root_entities(model).find do |candidate|
        candidate.respond_to?(:persistent_id) && candidate.persistent_id.to_i == persistent_id.to_i
      end
      return nil unless entity
      editable_root_entities(model).include?(entity) ? entity : nil
    end

    def resolve_entity_group_members!(model, group)
      ids = Array(group['member_persistent_ids']).map(&:to_i)
      raise "Entity group #{group['name'].inspect} has no members." if ids.empty?
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
      unless missing.empty?
        raise "Entity group #{group['name'].inspect} contains missing member persistent ids: #{missing.join(', ')}."
      end
      members
    end

    def require_transformable_group_members!(members)
      members.map do |entity|
        unless entity.is_a?(Sketchup::Group) && !entity.get_attribute('OpenSU', 'type').to_s.empty?
          raise 'Group transform/duplicate currently supports OpenSU Groups only.'
        end
        entity
      end
    end

    def entity_group_result(model, group, include_members: true)
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
      result = {
        type: 'entity_group',
        name: group['name'].to_s,
        description: group['description'],
        source_ref: group['source_ref'],
        member_count: ids.length,
        missing_member_count: missing.length,
        missing_persistent_ids: missing
      }.compact
      result[:members] = members.map { |entity| edit_entity_result(entity) } if include_members
      result
    end

    def entity_group_bounds_center_mm(members)
      min_x = min_y = min_z = Float::INFINITY
      max_x = max_y = max_z = -Float::INFINITY
      members.each do |entity|
        bounds = entity.bounds
        min_x = [min_x, bounds.min.x].min
        min_y = [min_y, bounds.min.y].min
        min_z = [min_z, bounds.min.z].min
        max_x = [max_x, bounds.max.x].max
        max_y = [max_y, bounds.max.y].max
        max_z = [max_z, bounds.max.z].max
      end
      [
        length_to_mm((min_x + max_x) / 2.0),
        length_to_mm((min_y + max_y) / 2.0),
        length_to_mm((min_z + max_z) / 2.0)
      ]
    end

    def next_entity_group_name(model, groups, base)
      candidate = base
      index = 2
      loop do
        group_conflict = groups.any? { |group| group['name'].to_s.casecmp?(candidate) }
        root_conflict = editable_root_entities(model).any? { |entity| entity.name.to_s.casecmp?(candidate) }
        return candidate unless group_conflict || root_conflict
        candidate = "#{base}_#{index}"
        index += 1
      end
    end

    def next_group_copy_entity_name(model, raw_name)
      base = raw_name.to_s.strip.empty? ? 'OpenSU_Copy' : "#{raw_name}_Copy"
      candidate = base
      index = 2
      loop do
        conflict = editable_root_entities(model).any? { |entity| entity.name.to_s == candidate }
        return candidate unless conflict
        candidate = "#{base}_#{index}"
        index += 1
      end
    end
  end
end

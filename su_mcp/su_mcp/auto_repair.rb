# frozen_string_literal: true

module SU_MCP
  class Server
    AUTO_REPAIR_TOOL_NAMES = %w[
      find_entities
      batch_set_tag
      batch_set_visibility
      batch_transform_entities
      diagnose_model
      delete_entity_confirmed
    ].freeze unless const_defined?(:AUTO_REPAIR_TOOL_NAMES, false)

    unless private_method_defined?(:handle_tool_call_without_auto_repair)
      alias_method :handle_tool_call_without_auto_repair, :handle_tool_call
      private :handle_tool_call_without_auto_repair
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_auto_repair(request) unless AUTO_REPAIR_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'find_entities' then find_entities(args)
        when 'batch_set_tag' then batch_set_tag(args)
        when 'batch_set_visibility' then batch_set_visibility(args)
        when 'batch_transform_entities' then batch_transform_entities(args)
        when 'diagnose_model' then diagnose_model(args)
        when 'delete_entity_confirmed' then delete_entity_confirmed(args)
        else raise "Unknown auto repair tool: #{tool_name}"
        end
      end
    end

    def find_entities(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      name_contains = normalized_name(params['name_contains'])
      opensu_type = normalized_name(params['opensu_type'])
      tag_name = normalized_name(params['tag_name'])
      visible_filter = params.key?('visible') ? boolean_value(params['visible'], 'visible') : nil
      limit = integer_in_range(params['limit'] || 200, 'limit', 1, 1000)

      entities = editable_root_entities(model).select do |entity|
        name_ok = !name_contains || entity.name.to_s.downcase.include?(name_contains.downcase)
        type_ok = !opensu_type || entity.get_attribute('OpenSU', 'type').to_s == opensu_type
        tag_ok = !tag_name || (entity.respond_to?(:layer) && entity.layer && entity.layer.name.to_s == tag_name)
        visible_ok = visible_filter.nil? || (entity.respond_to?(:visible?) && entity.visible? == visible_filter)
        name_ok && type_ok && tag_ok && visible_ok
      end.first(limit)

      {
        count: entities.length,
        truncated: editable_root_entities(model).length > limit,
        entities: entities.map { |entity| edit_entity_result(entity) }
      }
    end

    def batch_set_tag(params)
      model = Sketchup.active_model
      entities = resolve_entity_id_list(model, params)
      tag_name = normalized_name(params['tag_name'])
      raise 'tag_name is required.' unless tag_name

      model.start_operation('OpenSU: Batch Set Tag', true)
      begin
        tag = model.layers[tag_name] || model.layers.add(tag_name)
        entities.each { |entity| entity.layer = tag }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      { count: entities.length, tag_name: tag_name, entities: entities.map { |entity| edit_entity_result(entity) } }
    end

    def batch_set_visibility(params)
      model = Sketchup.active_model
      entities = resolve_entity_id_list(model, params)
      visible = boolean_value(params['visible'], 'visible')

      model.start_operation('OpenSU: Batch Set Visibility', true)
      begin
        entities.each { |entity| entity.visible = visible }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      { count: entities.length, visible: visible, entities: entities.map { |entity| edit_entity_result(entity) } }
    end

    def batch_transform_entities(params)
      model = Sketchup.active_model
      entities = resolve_entity_id_list(model, params)
      groups = entities.map do |entity|
        unless entity.is_a?(Sketchup::Group) && !entity.get_attribute('OpenSU', 'type').to_s.empty?
          raise 'batch_transform_entities only supports OpenSU Groups.'
        end
        entity
      end

      translation_mm = vector3_numbers(params['translation_mm'] || [0, 0, 0], 'translation_mm')
      rotation_deg = finite_number(params.key?('rotation_z_deg') ? params['rotation_z_deg'] : 0, 'rotation_z_deg')
      raise 'Transform must move or rotate the entities.' if translation_mm.all? { |v| v.abs < 0.000001 } && rotation_deg.abs < 0.000001

      model.start_operation('OpenSU: Batch Transform Entities', true)
      begin
        groups.each do |group|
          pivot_mm = bounds_center_mm(group.bounds)
          transform = semantic_edit_transformation(translation_mm, rotation_deg, pivot_mm)
          children = group.entities.to_a
          group.entities.transform_entities(transform, children) unless children.empty?
          transform_semantic_metadata!(group, translation_mm, rotation_deg, pivot_mm)
          group.set_attribute('OpenSU', 'last_edit', 'batch_transform')
        end
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        count: groups.length,
        translation_mm: translation_mm,
        rotation_z_deg: rotation_deg,
        entities: groups.map { |entity| edit_entity_result(entity) }
      }
    end

    def diagnose_model(params)
      validation = validate_model(params)
      model = Sketchup.active_model
      entities = editable_root_entities(model)
      issues = []

      Array(validation[:errors]).each do |message|
        issues << diagnostic_issue(message, 'error', entities)
      end
      Array(validation[:warnings]).each do |message|
        issues << diagnostic_issue(message, 'warning', entities)
      end

      {
        valid: validation[:valid],
        summary: validation[:summary],
        issue_count: issues.length,
        issues: issues,
        validation: validation
      }
    end

    def delete_entity_confirmed(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model
      entity_id = integer_in_range(params['entity_id'], 'entity_id', 1, 2_147_483_647)
      confirm_name = normalized_name(params['confirm_name'])
      confirmed = boolean_value(params['confirm_delete'], 'confirm_delete')
      raise 'confirm_delete must be true.' unless confirmed

      entity = model.find_entity_by_id(entity_id)
      raise "Entity #{entity_id} was not found." unless entity
      unless editable_root_entities(model).include?(entity)
        raise 'Delete target must be a root Group or ComponentInstance.'
      end
      raise 'Delete target must be an OpenSU semantic entity.' if entity.get_attribute('OpenSU', 'type').to_s.empty?
      raise 'confirm_name is required.' unless confirm_name
      raise "Confirmation name does not match target #{entity.name.to_s.inspect}." unless entity.name.to_s == confirm_name

      snapshot = edit_entity_result(entity)
      model.start_operation('OpenSU: Confirmed Delete Entity', true)
      begin
        entity.erase!
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      { deleted: true, entity: snapshot }
    end

    def editable_root_entities(model)
      model.entities.to_a.select do |entity|
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end
    end

    def resolve_entity_id_list(model, params)
      ids = params['entity_ids']
      raise 'entity_ids must be a non-empty array.' unless ids.is_a?(Array) && !ids.empty?
      raise 'A batch may contain at most 200 entities.' if ids.length > 200

      seen = {}
      ids.map do |value|
        id = integer_in_range(value, 'entity_id', 1, 2_147_483_647)
        raise "Duplicate entity_id #{id} in batch." if seen[id]
        seen[id] = true
        entity = model.find_entity_by_id(id)
        raise "Entity #{id} was not found." unless entity
        unless editable_root_entities(model).include?(entity)
          raise "Entity #{id} is not a root Group or ComponentInstance."
        end
        entity
      end
    end

    def diagnostic_issue(message, severity, entities)
      matched = entities.find do |entity|
        name = entity.respond_to?(:name) ? entity.name.to_s : ''
        !name.empty? && message.include?(name)
      end

      {
        severity: severity,
        message: message,
        entity_id: matched&.entityID,
        name: matched&.name.to_s,
        opensu_type: matched&.get_attribute('OpenSU', 'type'),
        repair_hint: diagnostic_repair_hint(message)
      }
    end

    def diagnostic_repair_hint(message)
      text = message.downcase
      return 'Inspect the target solid. If the geometry is disposable, recreate it; otherwise repair the shell before continuing.' if text.include?('not a closed manifold solid')
      return 'Define the referenced level or change the entity level_name to an existing level.' if text.include?('undefined level')
      return 'Rename one of the duplicated semantic objects so root names remain unique.' if text.include?('duplicate') && text.include?('name')
      return 'Inspect opening metadata and remove or reposition the conflicting opening.' if text.include?('opening') && text.include?('overlap')
      return 'Inspect the entity metadata and dimensions, then apply a targeted edit instead of rebuilding unrelated geometry.' if text.include?('invalid')
      'Inspect the named entity and apply the smallest targeted repair, then validate again.'
    end
  end
end

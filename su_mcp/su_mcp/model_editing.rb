# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    MODEL_EDIT_TOOL_NAMES = %w[
      rename_entity
      set_entity_tag
      set_entity_visibility
      transform_entity
      duplicate_entity
    ].freeze unless const_defined?(:MODEL_EDIT_TOOL_NAMES, false)

    unless private_method_defined?(:handle_tool_call_without_model_editing)
      alias_method :handle_tool_call_without_model_editing, :handle_tool_call
      private :handle_tool_call_without_model_editing
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_model_editing(request) unless MODEL_EDIT_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'rename_entity' then rename_entity(args)
        when 'set_entity_tag' then set_entity_tag(args)
        when 'set_entity_visibility' then set_entity_visibility(args)
        when 'transform_entity' then transform_entity(args)
        when 'duplicate_entity' then duplicate_entity(args)
        else raise "Unknown model editing tool: #{tool_name}"
        end
      end
    end

    def rename_entity(params)
      model = Sketchup.active_model
      entity = resolve_root_edit_target(model, params)
      new_name = normalized_name(params['new_name'])
      raise 'new_name is required.' unless new_name
      ensure_unique_root_name!(model, new_name, entity)
      old_name = entity.name.to_s

      model.start_operation('OpenSU: Rename Entity', true)
      begin
        entity.name = new_name
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      edit_entity_result(entity).merge(old_name: old_name)
    end

    def set_entity_tag(params)
      model = Sketchup.active_model
      entity = resolve_root_edit_target(model, params)
      tag_name = normalized_name(params['tag_name'])
      raise 'tag_name is required.' unless tag_name

      model.start_operation('OpenSU: Set Entity Tag', true)
      begin
        tag = model.layers[tag_name] || model.layers.add(tag_name)
        entity.layer = tag
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      edit_entity_result(entity)
    end

    def set_entity_visibility(params)
      model = Sketchup.active_model
      entity = resolve_root_edit_target(model, params)
      visible = boolean_value(params['visible'], 'visible')

      model.start_operation('OpenSU: Set Entity Visibility', true)
      begin
        entity.visible = visible
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      edit_entity_result(entity).merge(visible: entity.visible?)
    end

    def transform_entity(params)
      model = Sketchup.active_model
      entity = resolve_root_edit_target(model, params)
      raise 'transform_entity only supports OpenSU Groups.' unless entity.is_a?(Sketchup::Group)
      raise 'Target Group is not an OpenSU semantic entity.' if entity.get_attribute('OpenSU', 'type').to_s.empty?

      translation_mm = vector3_numbers(params['translation_mm'] || [0, 0, 0], 'translation_mm')
      rotation_deg = finite_number(params.key?('rotation_z_deg') ? params['rotation_z_deg'] : 0, 'rotation_z_deg')
      pivot_mm = params['pivot_mm'] ? vector3_numbers(params['pivot_mm'], 'pivot_mm') : bounds_center_mm(entity.bounds)
      raise 'Transform must move or rotate the entity.' if translation_mm.all? { |v| v.abs < 0.000001 } && rotation_deg.abs < 0.000001

      transform = semantic_edit_transformation(translation_mm, rotation_deg, pivot_mm)
      model.start_operation('OpenSU: Transform Entity', true)
      begin
        children = entity.entities.to_a
        entity.entities.transform_entities(transform, children) unless children.empty?
        transform_semantic_metadata!(entity, translation_mm, rotation_deg, pivot_mm)
        entity.set_attribute('OpenSU', 'last_edit', 'transform')
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      edit_entity_result(entity).merge(translation_mm: translation_mm, rotation_z_deg: rotation_deg, pivot_mm: pivot_mm)
    end

    def duplicate_entity(params)
      model = Sketchup.active_model
      source = resolve_root_edit_target(model, params)
      raise 'duplicate_entity currently supports OpenSU Groups only.' unless source.is_a?(Sketchup::Group)
      raise 'Target Group is not an OpenSU semantic entity.' if source.get_attribute('OpenSU', 'type').to_s.empty?

      new_name = normalized_name(params['new_name']) || next_entity_name(model, source.name.to_s.empty? ? 'Copy' : "#{source.name}_Copy")
      ensure_unique_root_name!(model, new_name, nil)
      translation_mm = vector3_numbers(params['translation_mm'] || [0, 0, 0], 'translation_mm')
      rotation_deg = finite_number(params.key?('rotation_z_deg') ? params['rotation_z_deg'] : 0, 'rotation_z_deg')
      pivot_mm = params['pivot_mm'] ? vector3_numbers(params['pivot_mm'], 'pivot_mm') : bounds_center_mm(source.bounds)

      model.start_operation('OpenSU: Duplicate Entity', true)
      begin
        copy = source.copy
        copy.name = new_name
        if translation_mm.any? { |v| v.abs >= 0.000001 } || rotation_deg.abs >= 0.000001
          transform = semantic_edit_transformation(translation_mm, rotation_deg, pivot_mm)
          children = copy.entities.to_a
          copy.entities.transform_entities(transform, children) unless children.empty?
          transform_semantic_metadata!(copy, translation_mm, rotation_deg, pivot_mm)
        end
        copy.set_attribute('OpenSU', 'duplicated_from', source.name.to_s)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      edit_entity_result(copy).merge(duplicated_from: source.name.to_s, translation_mm: translation_mm, rotation_z_deg: rotation_deg)
    end

    def resolve_root_edit_target(model, params)
      raise 'No active SketchUp model.' unless model
      entity = if params['entity_id']
                 model.find_entity_by_id(integer_in_range(params['entity_id'], 'entity_id', 1, 2_147_483_647))
               elsif params['name']
                 name = normalized_name(params['name'])
                 matches = model.entities.to_a.select { |e| e.respond_to?(:name) && e.name.to_s == name }
                 raise "No root entity named #{name.inspect} was found." if matches.empty?
                 raise "More than one root entity named #{name.inspect} exists; use entity_id." if matches.length > 1
                 matches.first
               else
                 raise 'Provide entity_id or name.'
               end
      raise 'Target entity was not found.' unless entity
      unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        raise 'Editing tools only support root Groups or ComponentInstances.'
      end
      raise 'Target must be a root model entity.' unless model.entities.to_a.include?(entity)
      entity
    end

    def ensure_unique_root_name!(model, name, except_entity)
      duplicate = model.entities.to_a.any? do |entity|
        next false if except_entity && entity == except_entity
        entity.respond_to?(:name) && entity.name.to_s == name
      end
      raise "A root entity named #{name.inspect} already exists." if duplicate
    end

    def edit_entity_result(entity)
      {
        entity_id: entity.entityID,
        persistent_id: entity.respond_to?(:persistent_id) ? entity.persistent_id : nil,
        entity_type: entity.typename,
        name: entity.respond_to?(:name) ? entity.name.to_s : '',
        opensu_type: entity.get_attribute('OpenSU', 'type'),
        tag: entity.respond_to?(:layer) && entity.layer ? entity.layer.name.to_s : nil,
        visible: entity.respond_to?(:visible?) ? entity.visible? : nil,
        bounds_mm: bounds_to_mm(entity.bounds)
      }
    end

    def semantic_edit_transformation(translation_mm, rotation_deg, pivot_mm)
      pivot = Geom::Point3d.new(mm(pivot_mm[0]), mm(pivot_mm[1]), mm(pivot_mm[2]))
      rotation = Geom::Transformation.rotation(pivot, Z_AXIS, rotation_deg.degrees)
      translation = Geom::Transformation.translation([mm(translation_mm[0]), mm(translation_mm[1]), mm(translation_mm[2])])
      translation * rotation
    end

    def transform_semantic_metadata!(entity, translation_mm, rotation_deg, pivot_mm)
      %w[origin_mm start_mm end_mm center_mm].each do |key|
        raw = entity.get_attribute('OpenSU', key)
        next if raw.nil?
        point = parse_stored_point(raw)
        next unless point
        entity.set_attribute('OpenSU', key, JSON.generate(transform_point_mm(point, translation_mm, rotation_deg, pivot_mm)))
      end

      raw_points = entity.get_attribute('OpenSU', 'points_json')
      if raw_points
        points = parse_stored_points(raw_points)
        if points
          transformed = points.map { |p| transform_point_mm(p, translation_mm, rotation_deg, pivot_mm) }
          entity.set_attribute('OpenSU', 'points_json', JSON.generate(transformed))
        end
      end
    end

    def parse_stored_point(raw)
      value = raw.is_a?(Array) ? raw : JSON.parse(raw.to_s)
      return nil unless value.is_a?(Array) && value.length == 3
      value.map { |item| Float(item) }
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
    end

    def parse_stored_points(raw)
      value = raw.is_a?(Array) ? raw : JSON.parse(raw.to_s)
      return nil unless value.is_a?(Array) && value.length >= 3
      value.map do |point|
        return nil unless point.is_a?(Array) && point.length == 3
        point.map { |item| Float(item) }
      end
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
    end

    def transform_point_mm(point, translation_mm, rotation_deg, pivot_mm)
      radians = rotation_deg * Math::PI / 180.0
      c = Math.cos(radians)
      s = Math.sin(radians)
      dx = point[0] - pivot_mm[0]
      dy = point[1] - pivot_mm[1]
      [
        pivot_mm[0] + (dx * c) - (dy * s) + translation_mm[0],
        pivot_mm[1] + (dx * s) + (dy * c) + translation_mm[1],
        point[2] + translation_mm[2]
      ].map { |value| value.round(6) }
    end

    def bounds_center_mm(bounds)
      [
        length_to_mm((bounds.min.x + bounds.max.x) / 2.0),
        length_to_mm((bounds.min.y + bounds.max.y) / 2.0),
        length_to_mm((bounds.min.z + bounds.max.z) / 2.0)
      ]
    end

    def boolean_value(value, label)
      return value if value == true || value == false
      return true if value.to_s.downcase == 'true'
      return false if value.to_s.downcase == 'false'
      raise "#{label} must be true or false."
    end
  end
end

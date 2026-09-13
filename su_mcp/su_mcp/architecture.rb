# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    ARCHITECTURE_TOOL_NAMES = %w[
      inspect_model
      create_floor
      create_wall
    ].freeze unless const_defined?(:ARCHITECTURE_TOOL_NAMES, false)

    unless private_method_defined?(:handle_tool_call_without_architecture)
      alias_method :handle_tool_call_without_architecture, :handle_tool_call
      private :handle_tool_call_without_architecture
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_architecture(request) unless ARCHITECTURE_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'inspect_model'
          inspect_model(args)
        when 'create_floor'
          create_floor(args)
        when 'create_wall'
          create_wall(args)
        else
          raise "Unknown architecture tool: #{tool_name}"
        end
      end
    end

    def architecture_tool_response(request)
      result = yield
      {
        jsonrpc: request['jsonrpc'] || '2.0',
        result: {
          content: [{ type: 'text', text: JSON.generate(result) }],
          isError: false,
          success: true,
          resourceId: result[:entity_id]
        },
        id: request['id']
      }
    rescue StandardError => e
      log "Architecture tool error: #{e.message}"
      log e.backtrace.join("\n") if e.backtrace
      {
        jsonrpc: request['jsonrpc'] || '2.0',
        error: {
          code: -32_603,
          message: e.message,
          data: { success: false }
        },
        id: request['id']
      }
    end

    def inspect_model(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      max_entities = integer_in_range(params['max_entities'] || 200, 'max_entities', 1, 1000)
      root = model.entities.to_a
      inspectable = root.select do |entity|
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      items = inspectable.first(max_entities).map { |entity| describe_entity(entity) }
      active_path = model.active_path

      {
        protocol_unit: 'mm',
        model: {
          title: model.title.to_s,
          path: model.path.to_s,
          modified: model.modified?,
          active_edit_path: active_path ? active_path.map { |entity| entity.entityID } : [],
          units_option_code: model.options['UnitsOptions']['LengthUnit']
        },
        root_counts: {
          groups: root.count { |entity| entity.is_a?(Sketchup::Group) },
          component_instances: root.count { |entity| entity.is_a?(Sketchup::ComponentInstance) },
          loose_faces: root.count { |entity| entity.is_a?(Sketchup::Face) },
          loose_edges: root.count { |entity| entity.is_a?(Sketchup::Edge) }
        },
        entities: items,
        truncated: inspectable.length > max_entities,
        total_inspectable_entities: inspectable.length
      }
    end

    def create_floor(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      origin_mm = vector3_numbers(params['origin'] || [0, 0, 0], 'origin')
      width_mm = positive_number(params['width_mm'], 'width_mm')
      depth_mm = positive_number(params['depth_mm'], 'depth_mm')
      thickness_mm = positive_number(params['thickness_mm'] || 150, 'thickness_mm')
      name = normalized_name(params['name']) || next_entity_name(model, 'Floor')

      origin = origin_mm.map { |value| mm(value) }
      base = [
        origin,
        [origin[0] + mm(width_mm), origin[1], origin[2]],
        [origin[0] + mm(width_mm), origin[1] + mm(depth_mm), origin[2]],
        [origin[0], origin[1] + mm(depth_mm), origin[2]]
      ]

      model.start_operation('OpenSU: Create Floor', true)
      begin
        group = model.entities.add_group
        group.name = name
        add_closed_prism(group.entities, base, mm(thickness_mm))
        annotate_architecture_entity(
          group,
          'floor',
          width_mm: width_mm,
          depth_mm: depth_mm,
          thickness_mm: thickness_mm,
          origin_mm: origin_mm
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(group, 'floor', {
        width_mm: width_mm,
        depth_mm: depth_mm,
        thickness_mm: thickness_mm,
        origin_mm: origin_mm
      })
    end

    def create_wall(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      start_mm = vector3_numbers(params['start'] || [0, 0, 0], 'start')
      end_mm = vector3_numbers(params['end'], 'end')
      height_mm = positive_number(params['height_mm'] || 3000, 'height_mm')
      thickness_mm = positive_number(params['thickness_mm'] || 200, 'thickness_mm')
      name = normalized_name(params['name']) || next_entity_name(model, 'Wall')

      dz = end_mm[2] - start_mm[2]
      raise 'Wall start and end must use the same base elevation (z) in Phase 1.' if dz.abs > 0.001

      dx = end_mm[0] - start_mm[0]
      dy = end_mm[1] - start_mm[1]
      length_mm = Math.sqrt((dx * dx) + (dy * dy))
      raise 'Wall start and end must not be the same point.' if length_mm <= 0.001

      half = thickness_mm / 2.0
      perp_x = (-dy / length_mm) * half
      perp_y = (dx / length_mm) * half
      z = start_mm[2]

      footprint_mm = [
        [start_mm[0] + perp_x, start_mm[1] + perp_y, z],
        [end_mm[0] + perp_x, end_mm[1] + perp_y, z],
        [end_mm[0] - perp_x, end_mm[1] - perp_y, z],
        [start_mm[0] - perp_x, start_mm[1] - perp_y, z]
      ]
      footprint = footprint_mm.map { |point| point.map { |value| mm(value) } }

      model.start_operation('OpenSU: Create Wall', true)
      begin
        group = model.entities.add_group
        group.name = name
        add_closed_prism(group.entities, footprint, mm(height_mm))
        annotate_architecture_entity(
          group,
          'wall',
          start_mm: start_mm,
          end_mm: end_mm,
          length_mm: length_mm,
          height_mm: height_mm,
          thickness_mm: thickness_mm
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(group, 'wall', {
        start_mm: start_mm,
        end_mm: end_mm,
        length_mm: length_mm.round(3),
        height_mm: height_mm,
        thickness_mm: thickness_mm
      })
    end

    def add_closed_prism(entities, base, height)
      raise 'A prism requires exactly four base points.' unless base.length == 4

      top = base.map { |point| [point[0], point[1], point[2] + height] }
      faces = [
        [base[0], base[3], base[2], base[1]],
        [top[0], top[1], top[2], top[3]],
        [base[0], base[1], top[1], top[0]],
        [base[1], base[2], top[2], top[1]],
        [base[2], base[3], top[3], top[2]],
        [base[3], base[0], top[0], top[3]]
      ]

      created = faces.map { |points| entities.add_face(points) }
      raise 'SketchUp could not create one or more prism faces.' if created.any?(&:nil?)

      created
    end

    def architecture_entity_result(entity, type, dimensions)
      {
        entity_id: entity.entityID,
        persistent_id: entity.respond_to?(:persistent_id) ? entity.persistent_id : nil,
        name: entity.name.to_s,
        type: type,
        dimensions: dimensions,
        bounds_mm: bounds_to_mm(entity.bounds)
      }
    end

    def describe_entity(entity)
      name = if entity.respond_to?(:name) && !entity.name.to_s.empty?
               entity.name.to_s
             elsif entity.is_a?(Sketchup::ComponentInstance)
               entity.definition.name.to_s
             else
               ''
             end

      {
        entity_id: entity.entityID,
        persistent_id: entity.respond_to?(:persistent_id) ? entity.persistent_id : nil,
        entity_type: entity.typename,
        name: name,
        tag: entity.respond_to?(:layer) && entity.layer ? entity.layer.name.to_s : nil,
        opensu_type: entity.get_attribute('OpenSU', 'type'),
        bounds_mm: bounds_to_mm(entity.bounds)
      }
    end

    def bounds_to_mm(bounds)
      {
        min: [length_to_mm(bounds.min.x), length_to_mm(bounds.min.y), length_to_mm(bounds.min.z)],
        max: [length_to_mm(bounds.max.x), length_to_mm(bounds.max.y), length_to_mm(bounds.max.z)],
        size: [length_to_mm(bounds.width), length_to_mm(bounds.depth), length_to_mm(bounds.height)]
      }
    end

    def annotate_architecture_entity(entity, type, attributes)
      entity.set_attribute('OpenSU', 'type', type)
      entity.set_attribute('OpenSU', 'schema_version', 1)
      attributes.each do |key, value|
        stored = value.is_a?(Array) || value.is_a?(Hash) ? JSON.generate(value) : value
        entity.set_attribute('OpenSU', key.to_s, stored)
      end
    end

    def next_entity_name(model, prefix)
      existing = model.entities.filter_map do |entity|
        next unless entity.respond_to?(:name)
        entity.name.to_s
      end
      index = 1
      loop do
        candidate = format('%s_%03d', prefix, index)
        return candidate unless existing.include?(candidate)

        index += 1
      end
    end

    def normalized_name(value)
      return nil if value.nil?

      name = value.to_s.strip
      return nil if name.empty?
      raise 'name must be 120 characters or fewer.' if name.length > 120

      name
    end

    def vector3_numbers(value, label)
      raise "#{label} must be [x, y, z]." unless value.is_a?(Array) && value.length == 3

      value.map.with_index { |item, index| finite_number(item, "#{label}[#{index}]") }
    end

    def positive_number(value, label)
      number = finite_number(value, label)
      raise "#{label} must be greater than 0." unless number.positive?

      number
    end

    def finite_number(value, label)
      raise "#{label} is required." if value.nil?

      number = Float(value)
      raise "#{label} must be finite." unless number.finite?

      number
    rescue ArgumentError, TypeError
      raise "#{label} must be a number."
    end

    def integer_in_range(value, label, min, max)
      integer = Integer(value)
      raise "#{label} must be between #{min} and #{max}." unless integer.between?(min, max)

      integer
    rescue ArgumentError, TypeError
      raise "#{label} must be an integer."
    end

    def mm(value)
      value.to_f.mm
    end

    def length_to_mm(value)
      (value.to_f * 25.4).round(3)
    end
  end
end

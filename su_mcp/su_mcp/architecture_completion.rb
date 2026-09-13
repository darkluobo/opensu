# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    unless private_method_defined?(:handle_tool_call_without_architecture_completion)
      alias_method :handle_tool_call_without_architecture_completion, :handle_tool_call
      private :handle_tool_call_without_architecture_completion
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      args = request.dig('params', 'arguments') || {}

      case tool_name
      when 'create_opening'
        architecture_tool_response(request) { create_opening(args) }
      when 'validate_model'
        architecture_tool_response(request) { validate_model(args) }
      else
        handle_tool_call_without_architecture_completion(request)
      end
    end

    def create_opening(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      wall_id = integer_in_range(params['wall_id'], 'wall_id', 1, 2_147_483_647)
      wall = model.find_entity_by_id(wall_id)
      raise "Wall entity #{wall_id} was not found." unless wall
      raise 'create_opening currently supports wall Groups created by OpenSU.' unless wall.is_a?(Sketchup::Group)
      raise 'Target entity is not an OpenSU wall.' unless wall.get_attribute('OpenSU', 'type') == 'wall'

      existing_openings = wall.get_attribute('OpenSU', 'openings_json')
      if existing_openings && existing_openings != '[]'
        raise 'Phase 1 supports one opening per wall.'
      end

      start_mm = JSON.parse(wall.get_attribute('OpenSU', 'start_mm').to_s)
      end_mm = JSON.parse(wall.get_attribute('OpenSU', 'end_mm').to_s)
      wall_height_mm = positive_number(wall.get_attribute('OpenSU', 'height_mm'), 'stored wall height')
      thickness_mm = positive_number(wall.get_attribute('OpenSU', 'thickness_mm'), 'stored wall thickness')
      length_mm = positive_number(wall.get_attribute('OpenSU', 'length_mm'), 'stored wall length')

      offset_mm = finite_number(params['offset_mm'], 'offset_mm')
      width_mm = positive_number(params['width_mm'], 'width_mm')
      opening_height_mm = positive_number(params['height_mm'], 'height_mm')
      sill_height_mm = finite_number(params['sill_height_mm'] || 0, 'sill_height_mm')
      raise 'offset_mm must be greater than 0 in Phase 1.' unless offset_mm > 0
      raise 'sill_height_mm must be 0 or greater.' if sill_height_mm.negative?
      raise 'Opening must end before the wall endpoint in Phase 1.' unless (offset_mm + width_mm) < length_mm
      raise 'Opening exceeds wall height.' if (sill_height_mm + opening_height_mm) > wall_height_mm

      opening_name = normalized_name(params['name']) || next_opening_name(model)
      opening_type = normalized_name(params['opening_type']) || (sill_height_mm.zero? ? 'door' : 'window')

      model.start_operation('OpenSU: Create Opening', true)
      begin
        wall.entities.erase_entities(wall.entities.to_a)
        build_wall_shell_with_opening(
          wall.entities,
          start_mm,
          end_mm,
          wall_height_mm,
          thickness_mm,
          offset_mm,
          width_mm,
          opening_height_mm,
          sill_height_mm
        )
        opening = {
          name: opening_name,
          opening_type: opening_type,
          offset_mm: offset_mm,
          width_mm: width_mm,
          height_mm: opening_height_mm,
          sill_height_mm: sill_height_mm
        }
        wall.set_attribute('OpenSU', 'openings_json', JSON.generate([opening]))
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        entity_id: wall.entityID,
        persistent_id: wall.respond_to?(:persistent_id) ? wall.persistent_id : nil,
        name: opening_name,
        type: 'opening',
        wall_name: wall.name.to_s,
        opening: opening,
        wall_bounds_mm: bounds_to_mm(wall.bounds)
      }
    end

    def validate_model(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      max_entities = integer_in_range(params['max_entities'] || 1000, 'max_entities', 1, 5000)
      root = model.entities.to_a
      architecture = root.select do |entity|
        entity.is_a?(Sketchup::Group) && entity.get_attribute('OpenSU', 'type')
      end.first(max_entities)

      errors = []
      warnings = []
      loose_faces = root.count { |entity| entity.is_a?(Sketchup::Face) }
      loose_edges = root.count { |entity| entity.is_a?(Sketchup::Edge) }
      errors << "Model root contains #{loose_faces} loose face(s)." if loose_faces.positive?
      errors << "Model root contains #{loose_edges} loose edge(s)." if loose_edges.positive?

      names = architecture.map { |entity| entity.name.to_s }.reject(&:empty?)
      duplicates = names.group_by(&:itself).select { |_name, items| items.length > 1 }.keys
      errors << "Duplicate architecture names: #{duplicates.join(', ')}" unless duplicates.empty?

      architecture.each do |entity|
        type = entity.get_attribute('OpenSU', 'type').to_s
        name = entity.name.to_s
        label = name.empty? ? entity.entityID : name
        errors << "#{type} entity #{entity.entityID} has no stable name." if name.empty?
        errors << "#{label} has no geometry." if entity.entities.empty?

        case type
        when 'floor'
          validate_positive_attribute(entity, 'width_mm', errors)
          validate_positive_attribute(entity, 'depth_mm', errors)
          validate_positive_attribute(entity, 'thickness_mm', errors)
        when 'wall'
          validate_positive_attribute(entity, 'length_mm', errors)
          validate_positive_attribute(entity, 'height_mm', errors)
          validate_positive_attribute(entity, 'thickness_mm', errors)
          openings_json = entity.get_attribute('OpenSU', 'openings_json')
          if openings_json
            begin
              JSON.parse(openings_json)
            rescue JSON::ParserError
              errors << "#{label} has invalid opening metadata."
            end
          end
        else
          warnings << "Unknown OpenSU architecture type '#{type}' on #{label}."
        end
      end

      {
        valid: errors.empty?,
        protocol_unit: 'mm',
        errors: errors,
        warnings: warnings,
        summary: {
          architecture_entities: architecture.length,
          floors: architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'floor' },
          walls: architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'wall' },
          loose_faces: loose_faces,
          loose_edges: loose_edges,
          truncated: root.length > max_entities
        }
      }
    end

    def validate_positive_attribute(entity, key, errors)
      value = entity.get_attribute('OpenSU', key)
      label = entity.name.to_s.empty? ? entity.entityID : entity.name.to_s
      errors << "#{label} has invalid #{key}." if value.nil? || value.to_f <= 0
    end

    def build_wall_shell_with_opening(entities, start_mm, end_mm, wall_height_mm, thickness_mm, offset_mm, width_mm, opening_height_mm, sill_height_mm)
      dx = end_mm[0].to_f - start_mm[0].to_f
      dy = end_mm[1].to_f - start_mm[1].to_f
      length_mm = Math.sqrt((dx * dx) + (dy * dy))
      ux = dx / length_mm
      uy = dy / length_mm
      nx = -uy
      ny = ux
      half = thickness_mm / 2.0
      opening_end = offset_mm + width_mm
      opening_top = sill_height_mm + opening_height_mm

      point = lambda do |along, side, z_offset|
        [
          mm(start_mm[0].to_f + (ux * along) + (nx * side)),
          mm(start_mm[1].to_f + (uy * along) + (ny * side)),
          mm(start_mm[2].to_f + z_offset)
        ]
      end

      side_a = -half
      side_b = half

      [side_a, side_b].each do |side|
        add_panel(entities, point.call(0, side, 0), point.call(offset_mm, side, 0), point.call(offset_mm, side, wall_height_mm), point.call(0, side, wall_height_mm))
        add_panel(entities, point.call(opening_end, side, 0), point.call(length_mm, side, 0), point.call(length_mm, side, wall_height_mm), point.call(opening_end, side, wall_height_mm))
        if sill_height_mm.positive?
          add_panel(entities, point.call(offset_mm, side, 0), point.call(opening_end, side, 0), point.call(opening_end, side, sill_height_mm), point.call(offset_mm, side, sill_height_mm))
        end
        if opening_top < wall_height_mm
          add_panel(entities, point.call(offset_mm, side, opening_top), point.call(opening_end, side, opening_top), point.call(opening_end, side, wall_height_mm), point.call(offset_mm, side, wall_height_mm))
        end
      end

      add_panel(entities, point.call(0, side_a, 0), point.call(0, side_b, 0), point.call(0, side_b, wall_height_mm), point.call(0, side_a, wall_height_mm))
      add_panel(entities, point.call(length_mm, side_a, 0), point.call(length_mm, side_a, wall_height_mm), point.call(length_mm, side_b, wall_height_mm), point.call(length_mm, side_b, 0))

      if sill_height_mm.positive?
        add_panel(entities, point.call(0, side_a, 0), point.call(length_mm, side_a, 0), point.call(length_mm, side_b, 0), point.call(0, side_b, 0))
        add_panel(entities, point.call(offset_mm, side_a, sill_height_mm), point.call(offset_mm, side_b, sill_height_mm), point.call(opening_end, side_b, sill_height_mm), point.call(opening_end, side_a, sill_height_mm))
      else
        add_panel(entities, point.call(0, side_a, 0), point.call(offset_mm, side_a, 0), point.call(offset_mm, side_b, 0), point.call(0, side_b, 0))
        add_panel(entities, point.call(opening_end, side_a, 0), point.call(length_mm, side_a, 0), point.call(length_mm, side_b, 0), point.call(opening_end, side_b, 0))
      end

      if opening_top < wall_height_mm
        add_panel(entities, point.call(0, side_a, wall_height_mm), point.call(0, side_b, wall_height_mm), point.call(length_mm, side_b, wall_height_mm), point.call(length_mm, side_a, wall_height_mm))
        add_panel(entities, point.call(offset_mm, side_a, opening_top), point.call(opening_end, side_a, opening_top), point.call(opening_end, side_b, opening_top), point.call(offset_mm, side_b, opening_top))
      else
        add_panel(entities, point.call(0, side_a, wall_height_mm), point.call(0, side_b, wall_height_mm), point.call(offset_mm, side_b, wall_height_mm), point.call(offset_mm, side_a, wall_height_mm))
        add_panel(entities, point.call(opening_end, side_a, wall_height_mm), point.call(opening_end, side_b, wall_height_mm), point.call(length_mm, side_b, wall_height_mm), point.call(length_mm, side_a, wall_height_mm))
      end

      add_panel(entities, point.call(offset_mm, side_a, sill_height_mm), point.call(offset_mm, side_a, opening_top), point.call(offset_mm, side_b, opening_top), point.call(offset_mm, side_b, sill_height_mm))
      add_panel(entities, point.call(opening_end, side_a, sill_height_mm), point.call(opening_end, side_b, sill_height_mm), point.call(opening_end, side_b, opening_top), point.call(opening_end, side_a, opening_top))
    end

    def add_panel(entities, p1, p2, p3, p4)
      face = entities.add_face(p1, p2, p3, p4)
      raise 'SketchUp could not create an opening wall face.' unless face

      face
    end

    def next_opening_name(model)
      existing = model.entities.filter_map do |entity|
        next unless entity.is_a?(Sketchup::Group)
        raw = entity.get_attribute('OpenSU', 'openings_json')
        next unless raw

        begin
          JSON.parse(raw).map { |opening| opening['name'] }
        rescue JSON::ParserError
          []
        end
      end.flatten.compact

      index = 1
      loop do
        candidate = format('Opening_%03d', index)
        return candidate unless existing.include?(candidate)

        index += 1
      end
    end
  end
end

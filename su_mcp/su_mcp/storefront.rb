# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    STOREFRONT_TOOL_NAMES = %w[
      create_curtain_wall
    ].freeze unless const_defined?(:STOREFRONT_TOOL_NAMES, false)

    unless private_method_defined?(:handle_tool_call_without_storefront)
      alias_method :handle_tool_call_without_storefront, :handle_tool_call
      private :handle_tool_call_without_storefront
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_storefront(request) unless STOREFRONT_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'create_curtain_wall'
          create_curtain_wall(args)
        else
          raise "Unknown storefront tool: #{tool_name}"
        end
      end
    end

    # Overrides the Phase 1 implementation. Openings are appended to the wall
    # metadata and the complete wall shell is regenerated from all openings.
    def create_opening(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      wall_id = integer_in_range(params['wall_id'], 'wall_id', 1, 2_147_483_647)
      wall = model.find_entity_by_id(wall_id)
      raise "Wall entity #{wall_id} was not found." unless wall
      raise 'create_opening supports wall Groups created by OpenSU.' unless wall.is_a?(Sketchup::Group)
      raise 'Target entity is not an OpenSU wall.' unless wall.get_attribute('OpenSU', 'type') == 'wall'

      start_mm = JSON.parse(wall.get_attribute('OpenSU', 'start_mm').to_s)
      end_mm = JSON.parse(wall.get_attribute('OpenSU', 'end_mm').to_s)
      wall_height_mm = positive_number(wall.get_attribute('OpenSU', 'height_mm'), 'stored wall height')
      thickness_mm = positive_number(wall.get_attribute('OpenSU', 'thickness_mm'), 'stored wall thickness')
      length_mm = positive_number(wall.get_attribute('OpenSU', 'length_mm'), 'stored wall length')

      offset_mm = finite_number(params['offset_mm'], 'offset_mm')
      width_mm = positive_number(params['width_mm'], 'width_mm')
      opening_height_mm = positive_number(params['height_mm'], 'height_mm')
      sill_height_mm = finite_number(params['sill_height_mm'] || 0, 'sill_height_mm')
      raise 'offset_mm must be greater than 0.' unless offset_mm.positive?
      raise 'sill_height_mm must be 0 or greater.' if sill_height_mm.negative?
      raise 'Opening must end before the wall endpoint.' unless (offset_mm + width_mm) < length_mm
      raise 'Opening exceeds wall height.' if (sill_height_mm + opening_height_mm) > wall_height_mm

      existing = parse_openings_or_empty(wall)
      opening_name = normalized_name(params['name']) || next_opening_name(model)
      raise "Opening name #{opening_name.inspect} already exists on this wall." if existing.any? { |item| item['name'].to_s == opening_name }

      opening_type = normalized_name(params['opening_type']) || (sill_height_mm.zero? ? 'door' : 'window')
      opening = {
        name: opening_name,
        opening_type: opening_type,
        offset_mm: offset_mm,
        width_mm: width_mm,
        height_mm: opening_height_mm,
        sill_height_mm: sill_height_mm
      }

      proposed = existing + [stringify_opening(opening)]
      validate_opening_set!(proposed, length_mm, wall_height_mm)

      model.start_operation('OpenSU: Create Opening', true)
      begin
        wall.entities.erase_entities(wall.entities.to_a)
        build_wall_shell_with_openings(
          wall.entities,
          start_mm,
          end_mm,
          wall_height_mm,
          thickness_mm,
          proposed
        )
        wall.set_attribute('OpenSU', 'openings_json', JSON.generate(proposed))
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
        opening_count: proposed.length,
        wall_bounds_mm: bounds_to_mm(wall.bounds)
      }
    end

    def create_curtain_wall(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      start_mm = vector3_numbers(params['start_mm'] || params['start'], 'start_mm')
      end_mm = vector3_numbers(params['end_mm'] || params['end'], 'end_mm')
      height_mm = positive_number(params['height_mm'] || 3600, 'height_mm')
      panel_width_mm = positive_number(params['panel_width_mm'] || 1500, 'panel_width_mm')
      row_height_mm = positive_number(params['row_height_mm'] || height_mm, 'row_height_mm')
      mullion_width_mm = positive_number(params['mullion_width_mm'] || 60, 'mullion_width_mm')
      mullion_depth_mm = positive_number(params['mullion_depth_mm'] || 100, 'mullion_depth_mm')
      glass_thickness_mm = positive_number(params['glass_thickness_mm'] || 10, 'glass_thickness_mm')
      gap_mm = finite_number(params['gap_mm'] || 8, 'gap_mm')
      glass_opacity = finite_number(params.key?('glass_opacity') ? params['glass_opacity'] : 0.35, 'glass_opacity')
      raise 'gap_mm must be 0 or greater.' if gap_mm.negative?
      raise 'glass_opacity must be between 0 and 1.' unless glass_opacity.between?(0.0, 1.0)
      raise 'Curtain wall start and end must use the same base elevation (z).' if (end_mm[2] - start_mm[2]).abs > 0.001

      dx = end_mm[0] - start_mm[0]
      dy = end_mm[1] - start_mm[1]
      length_mm = Math.sqrt((dx * dx) + (dy * dy))
      raise 'Curtain wall start and end must not be the same point.' if length_mm <= 0.001
      raise 'mullion_width_mm is too large for the requested panel width.' if mullion_width_mm >= panel_width_mm
      raise 'mullion_width_mm is too large for the requested row height.' if mullion_width_mm >= row_height_mm

      basis = wall_basis(start_mm, end_mm)
      name = normalized_name(params['name']) || next_entity_name(model, 'CurtainWall')
      frame_color = (params['frame_color_hex'] || '#3F4448').to_s
      glass_color = (params['glass_color_hex'] || '#9CC9E8').to_s
      x_positions = grid_positions(length_mm, panel_width_mm)
      z_positions = grid_positions(height_mm, row_height_mm)

      model.start_operation('OpenSU: Create Curtain Wall', true)
      begin
        assembly = model.entities.add_group
        assembly.name = name
        assembly.set_attribute('OpenSU', 'type', 'curtain_wall')
        assembly.set_attribute('OpenSU', 'schema_version', 3)
        assembly.set_attribute('OpenSU', 'start_mm', JSON.generate(start_mm))
        assembly.set_attribute('OpenSU', 'end_mm', JSON.generate(end_mm))
        assembly.set_attribute('OpenSU', 'length_mm', length_mm)
        assembly.set_attribute('OpenSU', 'height_mm', height_mm)
        assembly.set_attribute('OpenSU', 'panel_width_mm', panel_width_mm)
        assembly.set_attribute('OpenSU', 'row_height_mm', row_height_mm)

        point = lambda do |along, side, z_offset|
          world_point_mm(start_mm, basis, along, side, z_offset)
        end
        frame_material = ensure_material(model, "#{name}_Frame", frame_color, 1.0)
        glass_material = ensure_material(model, "#{name}_Glass", glass_color, glass_opacity)
        frame_side = mullion_depth_mm / 2.0
        glass_side = glass_thickness_mm / 2.0
        half_frame = mullion_width_mm / 2.0

        x_positions.each_with_index do |x, index|
          a0 = [0.0, x - half_frame].max
          a1 = [length_mm, x + half_frame].min
          create_local_box(assembly.entities, format('Mullion_%02d', index + 1), point, a0, a1, frame_side, 0, height_mm, frame_material)
        end

        z_positions.each_with_index do |z, index|
          z0 = [0.0, z - half_frame].max
          z1 = [height_mm, z + half_frame].min
          create_local_box(assembly.entities, format('Transom_%02d', index + 1), point, 0, length_mm, frame_side, z0, z1, frame_material)
        end

        panel_count = 0
        x_positions.each_cons(2) do |a0_edge, a1_edge|
          z_positions.each_cons(2) do |z0_edge, z1_edge|
            a0 = a0_edge + half_frame + gap_mm
            a1 = a1_edge - half_frame - gap_mm
            z0 = z0_edge + half_frame + gap_mm
            z1 = z1_edge - half_frame - gap_mm
            next unless a1 > a0 && z1 > z0

            panel_count += 1
            create_local_box(
              assembly.entities,
              format('Glass_%03d', panel_count),
              point,
              a0,
              a1,
              glass_side,
              z0,
              z1,
              glass_material
            )
          end
        end
        raise 'Curtain wall dimensions leave no room for glass panels.' if panel_count.zero?

        assembly.set_attribute('OpenSU', 'panel_count', panel_count)
        assembly.set_attribute('OpenSU', 'bay_count', x_positions.length - 1)
        assembly.set_attribute('OpenSU', 'row_count', z_positions.length - 1)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        entity_id: assembly.entityID,
        persistent_id: assembly.respond_to?(:persistent_id) ? assembly.persistent_id : nil,
        name: assembly.name.to_s,
        type: 'curtain_wall',
        length_mm: length_mm.round(3),
        height_mm: height_mm,
        bay_count: x_positions.length - 1,
        row_count: z_positions.length - 1,
        panel_count: panel_count,
        bounds_mm: bounds_to_mm(assembly.bounds)
      }
    end

    def parse_openings_or_empty(wall)
      raw = wall.get_attribute('OpenSU', 'openings_json')
      return [] if raw.nil? || raw.to_s.strip.empty?

      parsed = JSON.parse(raw.to_s)
      raise 'Target wall opening metadata is not an array.' unless parsed.is_a?(Array)
      parsed
    rescue JSON::ParserError
      raise 'Target wall has invalid opening metadata.'
    end

    def stringify_opening(opening)
      opening.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
    end

    def validate_opening_set!(openings, length_mm, wall_height_mm)
      normalized = openings.map do |item|
        offset = finite_number(item['offset_mm'], 'opening offset_mm')
        width = positive_number(item['width_mm'], 'opening width_mm')
        height = positive_number(item['height_mm'], 'opening height_mm')
        sill = finite_number(item['sill_height_mm'] || 0, 'opening sill_height_mm')
        raise 'Opening offset must be greater than 0.' unless offset.positive?
        raise 'Opening sill must be 0 or greater.' if sill.negative?
        raise 'Opening must end before the wall endpoint.' unless offset + width < length_mm
        raise 'Opening exceeds wall height.' if sill + height > wall_height_mm
        [offset, offset + width, sill, sill + height, item['name'].to_s]
      end

      normalized.each_with_index do |a, index|
        normalized[(index + 1)..].to_a.each do |b|
          horizontal_overlap = [a[1], b[1]].min - [a[0], b[0]].max
          vertical_overlap = [a[3], b[3]].min - [a[2], b[2]].max
          next unless horizontal_overlap > 0.001 && vertical_overlap > 0.001

          raise "Openings #{a[4].inspect} and #{b[4].inspect} overlap."
        end
      end
    end

    def build_wall_shell_with_openings(entities, start_mm, end_mm, wall_height_mm, thickness_mm, openings)
      dx = end_mm[0].to_f - start_mm[0].to_f
      dy = end_mm[1].to_f - start_mm[1].to_f
      length_mm = Math.sqrt((dx * dx) + (dy * dy))
      ux = dx / length_mm
      uy = dy / length_mm
      nx = -uy
      ny = ux
      half = thickness_mm / 2.0

      point = lambda do |along, side, z_offset|
        [
          mm(start_mm[0].to_f + (ux * along) + (nx * side)),
          mm(start_mm[1].to_f + (uy * along) + (ny * side)),
          mm(start_mm[2].to_f + z_offset)
        ]
      end

      x_breaks = [0.0, length_mm]
      z_breaks = [0.0, wall_height_mm]
      openings.each do |opening|
        offset = opening['offset_mm'].to_f
        width = opening['width_mm'].to_f
        sill = opening['sill_height_mm'].to_f
        height = opening['height_mm'].to_f
        x_breaks.concat([offset, offset + width])
        z_breaks.concat([sill, sill + height])
      end
      x_breaks = x_breaks.uniq.sort
      z_breaks = z_breaks.uniq.sort

      solid = Array.new(x_breaks.length - 1) { Array.new(z_breaks.length - 1, true) }
      (0...(x_breaks.length - 1)).each do |xi|
        (0...(z_breaks.length - 1)).each do |zi|
          mid_x = (x_breaks[xi] + x_breaks[xi + 1]) / 2.0
          mid_z = (z_breaks[zi] + z_breaks[zi + 1]) / 2.0
          solid[xi][zi] = !openings.any? do |opening|
            a0 = opening['offset_mm'].to_f
            a1 = a0 + opening['width_mm'].to_f
            z0 = opening['sill_height_mm'].to_f
            z1 = z0 + opening['height_mm'].to_f
            mid_x > a0 && mid_x < a1 && mid_z > z0 && mid_z < z1
          end
        end
      end

      side_a = -half
      side_b = half
      (0...(x_breaks.length - 1)).each do |xi|
        (0...(z_breaks.length - 1)).each do |zi|
          next unless solid[xi][zi]

          a0 = x_breaks[xi]
          a1 = x_breaks[xi + 1]
          z0 = z_breaks[zi]
          z1 = z_breaks[zi + 1]

          # Front/back skin for this occupied grid cell.
          add_panel(entities, point.call(a0, side_a, z0), point.call(a1, side_a, z0), point.call(a1, side_a, z1), point.call(a0, side_a, z1))
          add_panel(entities, point.call(a0, side_b, z0), point.call(a0, side_b, z1), point.call(a1, side_b, z1), point.call(a1, side_b, z0))

          left_solid = xi.positive? && solid[xi - 1][zi]
          right_solid = xi < solid.length - 1 && solid[xi + 1][zi]
          below_solid = zi.positive? && solid[xi][zi - 1]
          above_solid = zi < solid[xi].length - 1 && solid[xi][zi + 1]

          unless left_solid
            add_panel(entities, point.call(a0, side_a, z0), point.call(a0, side_a, z1), point.call(a0, side_b, z1), point.call(a0, side_b, z0))
          end
          unless right_solid
            add_panel(entities, point.call(a1, side_a, z0), point.call(a1, side_b, z0), point.call(a1, side_b, z1), point.call(a1, side_a, z1))
          end
          unless below_solid
            add_panel(entities, point.call(a0, side_a, z0), point.call(a0, side_b, z0), point.call(a1, side_b, z0), point.call(a1, side_a, z0))
          end
          unless above_solid
            add_panel(entities, point.call(a0, side_a, z1), point.call(a1, side_a, z1), point.call(a1, side_b, z1), point.call(a0, side_b, z1))
          end
        end
      end
    end

    def grid_positions(total, target_spacing)
      count = [(total / target_spacing).ceil, 1].max
      step = total / count.to_f
      (0..count).map { |index| step * index }
    end
  end
end

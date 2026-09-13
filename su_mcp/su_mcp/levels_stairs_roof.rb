# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    PHASE3_BUILDING_TOOL_NAMES = %w[
      define_level
      create_ceiling
      create_stair
      create_flat_roof
    ].freeze unless const_defined?(:PHASE3_BUILDING_TOOL_NAMES, false)

    unless private_method_defined?(:handle_tool_call_without_phase3_building)
      alias_method :handle_tool_call_without_phase3_building, :handle_tool_call
      private :handle_tool_call_without_phase3_building
    end

    unless private_method_defined?(:inspect_model_without_phase3_levels)
      alias_method :inspect_model_without_phase3_levels, :inspect_model
      private :inspect_model_without_phase3_levels
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_phase3_building(request) unless PHASE3_BUILDING_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'define_level'
          define_level(args)
        when 'create_ceiling'
          create_ceiling(args)
        when 'create_stair'
          create_stair(args)
        when 'create_flat_roof'
          create_flat_roof(args)
        else
          raise "Unknown Phase 3 building tool: #{tool_name}"
        end
      end
    end

    def inspect_model(params)
      result = inspect_model_without_phase3_levels(params)
      result[:levels] = parse_model_levels(Sketchup.active_model)
      result
    end

    def define_level(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      name = normalized_name(params['name'])
      raise 'name is required.' unless name
      elevation_mm = finite_number(params['elevation_mm'], 'elevation_mm')
      floor_to_floor_mm = if params.key?('floor_to_floor_mm') && !params['floor_to_floor_mm'].nil?
                            positive_number(params['floor_to_floor_mm'], 'floor_to_floor_mm')
                          end

      levels = parse_model_levels(model)
      raise "A level named #{name.inspect} already exists." if levels.any? { |level| level['name'].to_s == name }
      if levels.any? { |level| (level['elevation_mm'].to_f - elevation_mm).abs < 0.001 }
        raise "A level already exists at elevation #{elevation_mm} mm."
      end

      level = {
        name: name,
        elevation_mm: elevation_mm,
        floor_to_floor_mm: floor_to_floor_mm
      }.compact

      model.start_operation('OpenSU: Define Level', true)
      begin
        levels << JSON.parse(JSON.generate(level))
        levels.sort_by! { |item| item['elevation_mm'].to_f }
        model.set_attribute('OpenSU', 'levels_json', JSON.generate(levels))
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        type: 'level',
        protocol_unit: 'mm',
        level: level,
        levels: levels
      }
    end

    def create_ceiling(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      origin_mm = vector3_numbers(params['origin_mm'] || params['origin'] || [0, 0, 0], 'origin_mm')
      width_mm = positive_number(params['width_mm'], 'width_mm')
      depth_mm = positive_number(params['depth_mm'], 'depth_mm')
      thickness_mm = positive_number(params['thickness_mm'] || 100, 'thickness_mm')
      level_name = normalized_name(params['level_name'])
      ensure_level_exists!(model, level_name) if level_name
      name = normalized_name(params['name']) || next_entity_name(model, 'Ceiling')

      base = axis_aligned_rectangle(origin_mm, width_mm, depth_mm)

      model.start_operation('OpenSU: Create Ceiling', true)
      begin
        group = model.entities.add_group
        group.name = name
        add_closed_prism(group.entities, base, mm(thickness_mm))
        annotate_architecture_entity(
          group,
          'ceiling',
          origin_mm: origin_mm,
          width_mm: width_mm,
          depth_mm: depth_mm,
          thickness_mm: thickness_mm,
          level_name: level_name
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(group, 'ceiling', {
        origin_mm: origin_mm,
        width_mm: width_mm,
        depth_mm: depth_mm,
        thickness_mm: thickness_mm,
        level_name: level_name
      })
    end

    def create_stair(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      start_mm = vector3_numbers(params['start_mm'] || params['start'], 'start_mm')
      end_mm = vector3_numbers(params['end_mm'] || params['end'], 'end_mm')
      width_mm = positive_number(params['width_mm'] || 1200, 'width_mm')
      level_name = normalized_name(params['level_name'])
      ensure_level_exists!(model, level_name) if level_name
      name = normalized_name(params['name']) || next_entity_name(model, 'Stair')

      dx = end_mm[0] - start_mm[0]
      dy = end_mm[1] - start_mm[1]
      run_mm = Math.sqrt((dx * dx) + (dy * dy))
      rise_mm = end_mm[2] - start_mm[2]
      raise 'Stair end must be horizontally separated from start.' if run_mm <= 0.001
      raise 'Stair end elevation must be above start elevation.' if rise_mm <= 0.001

      riser_count = if params.key?('riser_count') && !params['riser_count'].nil?
                      integer_in_range(params['riser_count'], 'riser_count', 2, 100)
                    else
                      target = positive_number(params['target_riser_height_mm'] || 165, 'target_riser_height_mm')
                      [[(rise_mm / target).round, 2].max, 100].min
                    end

      riser_height_mm = rise_mm / riser_count.to_f
      tread_depth_mm = run_mm / riser_count.to_f
      raise 'Calculated tread depth is too small (< 150 mm).' if tread_depth_mm < 150.0
      raise 'Calculated riser height is outside 80-220 mm.' unless riser_height_mm.between?(80.0, 220.0)

      ux = dx / run_mm
      uy = dy / run_mm
      nx = -uy
      ny = ux
      half_width = width_mm / 2.0

      model.start_operation('OpenSU: Create Stair', true)
      begin
        stair = model.entities.add_group
        stair.name = name

        riser_count.times do |index|
          along0 = tread_depth_mm * index
          along1 = tread_depth_mm * (index + 1)
          height_mm = riser_height_mm * (index + 1)
          step = stair.entities.add_group
          step.name = format('Step_%03d', index + 1)
          footprint = [
            stair_point(start_mm, ux, uy, nx, ny, along0, -half_width, 0),
            stair_point(start_mm, ux, uy, nx, ny, along1, -half_width, 0),
            stair_point(start_mm, ux, uy, nx, ny, along1, half_width, 0),
            stair_point(start_mm, ux, uy, nx, ny, along0, half_width, 0)
          ]
          add_closed_prism(step.entities, footprint, mm(height_mm))
        end

        annotate_architecture_entity(
          stair,
          'stair',
          start_mm: start_mm,
          end_mm: end_mm,
          width_mm: width_mm,
          run_mm: run_mm,
          rise_mm: rise_mm,
          riser_count: riser_count,
          riser_height_mm: riser_height_mm,
          tread_depth_mm: tread_depth_mm,
          level_name: level_name
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(stair, 'stair', {
        start_mm: start_mm,
        end_mm: end_mm,
        width_mm: width_mm,
        run_mm: run_mm.round(3),
        rise_mm: rise_mm.round(3),
        riser_count: riser_count,
        riser_height_mm: riser_height_mm.round(3),
        tread_depth_mm: tread_depth_mm.round(3),
        level_name: level_name
      })
    end

    def create_flat_roof(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      origin_mm = vector3_numbers(params['origin_mm'] || params['origin'] || [0, 0, 0], 'origin_mm')
      width_mm = positive_number(params['width_mm'], 'width_mm')
      depth_mm = positive_number(params['depth_mm'], 'depth_mm')
      slab_thickness_mm = positive_number(params['slab_thickness_mm'] || 180, 'slab_thickness_mm')
      parapet_height_mm = finite_number(params.key?('parapet_height_mm') ? params['parapet_height_mm'] : 900, 'parapet_height_mm')
      parapet_thickness_mm = positive_number(params['parapet_thickness_mm'] || 150, 'parapet_thickness_mm')
      raise 'parapet_height_mm must be 0 or greater.' if parapet_height_mm.negative?
      if parapet_height_mm.positive?
        raise 'Parapet thickness is too large for roof width.' if parapet_thickness_mm * 2 >= width_mm
        raise 'Parapet thickness is too large for roof depth.' if parapet_thickness_mm * 2 >= depth_mm
      end
      level_name = normalized_name(params['level_name'])
      ensure_level_exists!(model, level_name) if level_name
      name = normalized_name(params['name']) || next_entity_name(model, 'Roof')

      model.start_operation('OpenSU: Create Flat Roof', true)
      begin
        roof = model.entities.add_group
        roof.name = name

        slab = roof.entities.add_group
        slab.name = 'Roof_Slab'
        add_closed_prism(slab.entities, axis_aligned_rectangle(origin_mm, width_mm, depth_mm), mm(slab_thickness_mm))

        if parapet_height_mm.positive?
          z = origin_mm[2] + slab_thickness_mm
          add_axis_box(roof.entities, 'Parapet_South', [origin_mm[0], origin_mm[1], z], width_mm, parapet_thickness_mm, parapet_height_mm)
          add_axis_box(roof.entities, 'Parapet_North', [origin_mm[0], origin_mm[1] + depth_mm - parapet_thickness_mm, z], width_mm, parapet_thickness_mm, parapet_height_mm)
          inner_depth = depth_mm - (2 * parapet_thickness_mm)
          add_axis_box(roof.entities, 'Parapet_West', [origin_mm[0], origin_mm[1] + parapet_thickness_mm, z], parapet_thickness_mm, inner_depth, parapet_height_mm)
          add_axis_box(roof.entities, 'Parapet_East', [origin_mm[0] + width_mm - parapet_thickness_mm, origin_mm[1] + parapet_thickness_mm, z], parapet_thickness_mm, inner_depth, parapet_height_mm)
        end

        annotate_architecture_entity(
          roof,
          'flat_roof',
          origin_mm: origin_mm,
          width_mm: width_mm,
          depth_mm: depth_mm,
          slab_thickness_mm: slab_thickness_mm,
          parapet_height_mm: parapet_height_mm,
          parapet_thickness_mm: parapet_thickness_mm,
          level_name: level_name
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(roof, 'flat_roof', {
        origin_mm: origin_mm,
        width_mm: width_mm,
        depth_mm: depth_mm,
        slab_thickness_mm: slab_thickness_mm,
        parapet_height_mm: parapet_height_mm,
        parapet_thickness_mm: parapet_thickness_mm,
        level_name: level_name
      })
    end

    def parse_model_levels(model)
      raw = model.get_attribute('OpenSU', 'levels_json')
      return [] if raw.nil? || raw.to_s.strip.empty?

      parsed = JSON.parse(raw.to_s)
      parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError
      []
    end

    def ensure_level_exists!(model, level_name)
      return if parse_model_levels(model).any? { |level| level['name'].to_s == level_name }

      raise "Level #{level_name.inspect} is not defined."
    end

    def axis_aligned_rectangle(origin_mm, width_mm, depth_mm)
      x, y, z = origin_mm
      [
        [mm(x), mm(y), mm(z)],
        [mm(x + width_mm), mm(y), mm(z)],
        [mm(x + width_mm), mm(y + depth_mm), mm(z)],
        [mm(x), mm(y + depth_mm), mm(z)]
      ]
    end

    def stair_point(start_mm, ux, uy, nx, ny, along_mm, side_mm, z_offset_mm)
      [
        mm(start_mm[0] + (ux * along_mm) + (nx * side_mm)),
        mm(start_mm[1] + (uy * along_mm) + (ny * side_mm)),
        mm(start_mm[2] + z_offset_mm)
      ]
    end

    def add_axis_box(parent_entities, name, origin_mm, width_mm, depth_mm, height_mm)
      group = parent_entities.add_group
      group.name = name
      add_closed_prism(group.entities, axis_aligned_rectangle(origin_mm, width_mm, depth_mm), mm(height_mm))
      group
    end
  end
end

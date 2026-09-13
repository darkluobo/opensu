# frozen_string_literal: true

module SU_MCP
  class Server
    SEMANTIC_LAYOUT_TOOL_NAMES = %w[
      resolve_grid_intersection
      create_grid_column
      create_grid_beam
      create_space_partitions
    ].freeze unless const_defined?(:SEMANTIC_LAYOUT_TOOL_NAMES, false)

    unless private_method_defined?(:handle_tool_call_without_semantic_layout)
      alias_method :handle_tool_call_without_semantic_layout, :handle_tool_call
      private :handle_tool_call_without_semantic_layout
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_semantic_layout(request) unless SEMANTIC_LAYOUT_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'resolve_grid_intersection'
          resolve_grid_intersection(args)
        when 'create_grid_column'
          create_grid_column(args)
        when 'create_grid_beam'
          create_grid_beam(args)
        when 'create_space_partitions'
          create_space_partitions(args)
        else
          raise "Unknown semantic layout tool: #{tool_name}"
        end
      end
    end

    def resolve_grid_intersection(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      x_grid_name = normalized_name(params['x_grid'])
      y_grid_name = normalized_name(params['y_grid'])
      raise 'x_grid is required.' unless x_grid_name
      raise 'y_grid is required.' unless y_grid_name

      level_name = normalized_name(params['level_name'])
      z_offset_mm = finite_number(params['z_offset_mm'] || 0, 'z_offset_mm')
      x_grid = find_semantic_grid!(model, x_grid_name, 'x')
      y_grid = find_semantic_grid!(model, y_grid_name, 'y')
      z_mm = level_name ? semantic_level_elevation!(model, level_name) + z_offset_mm : z_offset_mm

      {
        type: 'grid_intersection',
        protocol_unit: 'mm',
        x_grid: x_grid['name'],
        y_grid: y_grid['name'],
        level_name: level_name,
        point_mm: [x_grid['coordinate_mm'].to_f, y_grid['coordinate_mm'].to_f, z_mm]
      }
    end

    def create_grid_column(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      level_name = normalized_name(params['level_name'])
      raise 'level_name is required.' unless level_name
      point = resolve_grid_intersection(
        'x_grid' => params['x_grid'],
        'y_grid' => params['y_grid'],
        'level_name' => level_name,
        'z_offset_mm' => params['base_offset_mm'] || 0
      )
      height_mm = if params.key?('height_mm') && !params['height_mm'].nil?
                    positive_number(params['height_mm'], 'height_mm')
                  else
                    semantic_level_floor_to_floor!(model, level_name)
                  end
      width_mm = positive_number(params['width_mm'] || 400, 'width_mm')
      depth_mm = positive_number(params['depth_mm'] || 400, 'depth_mm')
      x_name = point[:x_grid].to_s
      y_name = point[:y_grid].to_s
      name = normalized_name(params['name']) || "Column_#{x_name}_#{y_name}_#{level_name}"
      ensure_root_name_available!(model, name)

      result = create_column(
        'center_mm' => point[:point_mm],
        'width_mm' => width_mm,
        'depth_mm' => depth_mm,
        'height_mm' => height_mm,
        'name' => name
      )
      entity = model.find_entity_by_id(result[:entity_id])
      annotate_semantic_source!(entity,
                                'grid_x' => x_name,
                                'grid_y' => y_name,
                                'level_name' => level_name,
                                'layout_source' => 'grid_intersection')
      result[:grid_reference] = { x_grid: x_name, y_grid: y_name, level_name: level_name }
      result
    end

    def create_grid_beam(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      level_name = normalized_name(params['level_name'])
      raise 'level_name is required.' unless level_name
      bottom_offset_mm = finite_number(params['bottom_offset_mm'] || 0, 'bottom_offset_mm')
      start_point = resolve_grid_intersection(
        'x_grid' => params['start_x_grid'],
        'y_grid' => params['start_y_grid'],
        'level_name' => level_name,
        'z_offset_mm' => bottom_offset_mm
      )
      end_point = resolve_grid_intersection(
        'x_grid' => params['end_x_grid'],
        'y_grid' => params['end_y_grid'],
        'level_name' => level_name,
        'z_offset_mm' => bottom_offset_mm
      )
      width_mm = positive_number(params['width_mm'] || 300, 'width_mm')
      height_mm = positive_number(params['height_mm'] || 500, 'height_mm')
      start_ref = "#{start_point[:x_grid]}/#{start_point[:y_grid]}"
      end_ref = "#{end_point[:x_grid]}/#{end_point[:y_grid]}"
      name = normalized_name(params['name']) || "Beam_#{start_ref.tr('/', '_')}_#{end_ref.tr('/', '_')}_#{level_name}"
      ensure_root_name_available!(model, name)

      result = create_beam(
        'start_mm' => start_point[:point_mm],
        'end_mm' => end_point[:point_mm],
        'width_mm' => width_mm,
        'height_mm' => height_mm,
        'name' => name
      )
      entity = model.find_entity_by_id(result[:entity_id])
      annotate_semantic_source!(entity,
                                'grid_start' => start_ref,
                                'grid_end' => end_ref,
                                'level_name' => level_name,
                                'layout_source' => 'grid_span')
      result[:grid_reference] = { start: start_ref, end: end_ref, level_name: level_name }
      result
    end

    def create_space_partitions(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      space_name = normalized_name(params['space_name'])
      raise 'space_name is required.' unless space_name
      space = find_semantic_space!(model, space_name)
      level_name = space['level_name'].to_s
      level_z = semantic_level_elevation!(model, level_name)
      base_offset_mm = finite_number(params['base_offset_mm'] || 0, 'base_offset_mm')
      thickness_mm = positive_number(params['thickness_mm'] || 100, 'thickness_mm')
      height_mm = if params.key?('height_mm') && !params['height_mm'].nil?
                    positive_number(params['height_mm'], 'height_mm')
                  else
                    semantic_level_floor_to_floor!(model, level_name)
                  end
      boundary = space['boundary_mm']
      raise "Space #{space_name.inspect} has invalid boundary metadata." unless boundary.is_a?(Array) && boundary.length >= 3

      edge_count = boundary.length
      edge_indices = if params['edge_indices'].nil?
                       (0...edge_count).to_a
                     else
                       values = params['edge_indices']
                       raise 'edge_indices must be an array of zero-based edge indices.' unless values.is_a?(Array) && !values.empty?
                       values.map { |value| integer_in_range(value, 'edge index', 0, edge_count - 1) }.uniq
                     end
      prefix = normalized_name(params['name_prefix']) || "Partition_#{space_name}"
      planned = edge_indices.map do |index|
        point_a = boundary[index]
        point_b = boundary[(index + 1) % edge_count]
        start_mm = [point_a[0].to_f, point_a[1].to_f, level_z + base_offset_mm]
        end_mm = [point_b[0].to_f, point_b[1].to_f, level_z + base_offset_mm]
        dx = end_mm[0] - start_mm[0]
        dy = end_mm[1] - start_mm[1]
        length_mm = Math.sqrt((dx * dx) + (dy * dy))
        raise "Space #{space_name.inspect} edge #{index} has zero length." if length_mm <= 0.001
        name = "#{prefix}_E#{format('%02d', index + 1)}"
        ensure_root_name_available!(model, name)
        {
          index: index,
          name: name,
          start_mm: start_mm,
          end_mm: end_mm,
          length_mm: length_mm
        }
      end

      created = []
      model.start_operation("OpenSU: Space Partitions #{space_name}", true)
      begin
        planned.each do |item|
          group = add_semantic_wall_group(model, item[:name], item[:start_mm], item[:end_mm], height_mm, thickness_mm)
          annotate_semantic_source!(group,
                                    'space_name' => space_name,
                                    'level_name' => level_name,
                                    'space_edge_index' => item[:index],
                                    'layout_source' => 'space_boundary')
          created << architecture_entity_result(group, 'wall', {
            start_mm: item[:start_mm],
            end_mm: item[:end_mm],
            length_mm: item[:length_mm].round(3),
            height_mm: height_mm,
            thickness_mm: thickness_mm,
            space_name: space_name,
            space_edge_index: item[:index]
          })
        end
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        type: 'space_partitions',
        protocol_unit: 'mm',
        space_name: space_name,
        level_name: level_name,
        created_count: created.length,
        walls: created
      }
    end

    def find_semantic_grid!(model, name, axis)
      grid = parse_model_semantic_array(model, 'grids_json').find do |item|
        item['name'].to_s.casecmp?(name.to_s) && item['axis'].to_s == axis
      end
      raise "Grid #{name.inspect} was not found on #{axis.upcase} axis." unless grid
      grid
    end

    def find_semantic_space!(model, name)
      space = parse_model_semantic_array(model, 'spaces_json').find { |item| item['name'].to_s.casecmp?(name.to_s) }
      raise "Space #{name.inspect} was not found." unless space
      space
    end

    def semantic_level!(model, level_name)
      level = parse_model_levels(model).find { |item| item['name'].to_s == level_name.to_s }
      raise "Level #{level_name.inspect} is not defined." unless level
      level
    end

    def semantic_level_elevation!(model, level_name)
      finite_number(semantic_level!(model, level_name)['elevation_mm'], "level #{level_name} elevation")
    end

    def semantic_level_floor_to_floor!(model, level_name)
      value = semantic_level!(model, level_name)['floor_to_floor_mm']
      raise "Level #{level_name.inspect} has no floor_to_floor_mm; provide height_mm explicitly." if value.nil?
      positive_number(value, "level #{level_name} floor_to_floor_mm")
    end

    def ensure_root_name_available!(model, name)
      collision = model.entities.any? do |entity|
        (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) &&
          entity.respond_to?(:name) && entity.name.to_s.casecmp?(name.to_s)
      end
      raise "A root entity named #{name.inspect} already exists." if collision
    end

    def annotate_semantic_source!(entity, values)
      return unless entity
      values.each { |key, value| entity.set_attribute('OpenSU', key, value) unless value.nil? }
    end

    def add_semantic_wall_group(model, name, start_mm, end_mm, height_mm, thickness_mm)
      dx = end_mm[0] - start_mm[0]
      dy = end_mm[1] - start_mm[1]
      length_mm = Math.sqrt((dx * dx) + (dy * dy))
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
      group
    end
  end
end

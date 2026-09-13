# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    ADVANCED_BUILDING_TOOL_NAMES = %w[
      create_l_stair
      create_u_stair
      create_slab_opening
      create_polygon_slab
      create_polygon_ceiling
    ].freeze unless const_defined?(:ADVANCED_BUILDING_TOOL_NAMES, false)

    unless private_method_defined?(:handle_tool_call_without_advanced_building)
      alias_method :handle_tool_call_without_advanced_building, :handle_tool_call
      private :handle_tool_call_without_advanced_building
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_advanced_building(request) unless ADVANCED_BUILDING_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'create_l_stair'
          create_l_stair(args)
        when 'create_u_stair'
          create_u_stair(args)
        when 'create_slab_opening'
          create_slab_opening(args)
        when 'create_polygon_slab'
          create_polygon_element(args, 'polygon_slab', 'PolygonSlab')
        when 'create_polygon_ceiling'
          create_polygon_element(args, 'polygon_ceiling', 'PolygonCeiling')
        else
          raise "Unknown advanced building tool: #{tool_name}"
        end
      end
    end

    def create_polygon_element(params, type, prefix)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      points_mm = polygon_points(params['points_mm'] || params['points'])
      thickness_mm = positive_number(params['thickness_mm'] || (type == 'polygon_ceiling' ? 100 : 150), 'thickness_mm')
      level_name = normalized_name(params['level_name'])
      ensure_level_exists!(model, level_name) if level_name
      name = normalized_name(params['name']) || next_entity_name(model, prefix)

      model.start_operation("OpenSU: Create #{prefix}", true)
      begin
        group = model.entities.add_group
        group.name = name
        build_polygon_prism(group.entities, points_mm, thickness_mm)
        annotate_architecture_entity(
          group,
          type,
          points_json: points_mm,
          vertex_count: points_mm.length,
          thickness_mm: thickness_mm,
          level_name: level_name
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(group, type, {
        points_mm: points_mm,
        vertex_count: points_mm.length,
        thickness_mm: thickness_mm,
        level_name: level_name
      })
    end

    def create_slab_opening(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      entity_id = integer_in_range(params['entity_id'], 'entity_id', 1, 2_147_483_647)
      target = model.find_entity_by_id(entity_id)
      raise "Entity #{entity_id} was not found." unless target
      raise 'Slab opening target must be an OpenSU Group.' unless target.is_a?(Sketchup::Group)

      type = target.get_attribute('OpenSU', 'type').to_s
      supported = %w[floor ceiling flat_roof]
      raise "create_slab_opening does not support OpenSU type #{type.inspect}." unless supported.include?(type)

      origin_mm, width_mm, depth_mm, thickness_mm, geometry_group = slab_geometry_contract(target, type)
      offset_x_mm = finite_number(params['offset_x_mm'], 'offset_x_mm')
      offset_y_mm = finite_number(params['offset_y_mm'], 'offset_y_mm')
      opening_width_mm = positive_number(params['width_mm'], 'width_mm')
      opening_depth_mm = positive_number(params['depth_mm'], 'depth_mm')
      raise 'offset_x_mm must be greater than 0.' unless offset_x_mm.positive?
      raise 'offset_y_mm must be greater than 0.' unless offset_y_mm.positive?
      raise 'Opening must stay inside slab width.' unless (offset_x_mm + opening_width_mm) < width_mm
      raise 'Opening must stay inside slab depth.' unless (offset_y_mm + opening_depth_mm) < depth_mm

      opening_name = normalized_name(params['name']) || next_slab_opening_name(target)
      opening_type = normalized_name(params['opening_type']) || 'void'
      openings = parse_openings_attribute(target, 'slab_openings_json')
      raise "An opening named #{opening_name.inspect} already exists." if openings.any? { |opening| opening['name'].to_s == opening_name }

      candidate = {
        name: opening_name,
        opening_type: opening_type,
        offset_x_mm: offset_x_mm,
        offset_y_mm: offset_y_mm,
        width_mm: opening_width_mm,
        depth_mm: opening_depth_mm
      }
      if openings.any? { |opening| slab_openings_overlap?(opening, candidate) }
        raise 'Slab opening overlaps an existing opening.'
      end
      openings << JSON.parse(JSON.generate(candidate))

      model.start_operation('OpenSU: Create Slab Opening', true)
      begin
        geometry_group.entities.erase_entities(geometry_group.entities.to_a)
        build_axis_slab_shell(geometry_group.entities, origin_mm, width_mm, depth_mm, thickness_mm, openings)
        target.set_attribute('OpenSU', 'slab_openings_json', JSON.generate(openings))
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        entity_id: target.entityID,
        persistent_id: target.respond_to?(:persistent_id) ? target.persistent_id : nil,
        name: opening_name,
        type: 'slab_opening',
        target_name: target.name.to_s,
        target_type: type,
        opening: candidate,
        opening_count: openings.length,
        target_bounds_mm: bounds_to_mm(target.bounds)
      }
    end

    def create_l_stair(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      origin_mm = vector3_numbers(params['origin_mm'] || params['origin'], 'origin_mm')
      direction = direction_vector(params['direction'] || 'x+')
      turn = turn_sign(params['turn'] || 'left')
      width_mm = positive_number(params['width_mm'] || 1200, 'width_mm')
      run1_mm = positive_number(params['run1_mm'], 'run1_mm')
      run2_mm = positive_number(params['run2_mm'], 'run2_mm')
      landing_length_mm = positive_number(params['landing_length_mm'] || width_mm, 'landing_length_mm')
      landing_thickness_mm = positive_number(params['landing_thickness_mm'] || 150, 'landing_thickness_mm')
      end_elevation_mm = finite_number(params['end_elevation_mm'], 'end_elevation_mm')
      level_name = normalized_name(params['level_name'])
      ensure_level_exists!(model, level_name) if level_name
      name = normalized_name(params['name']) || next_entity_name(model, 'LStair')

      rise_mm = end_elevation_mm - origin_mm[2]
      raise 'end_elevation_mm must be above stair origin.' unless rise_mm.positive?
      counts = split_stair_risers(rise_mm, params, run1_mm, run2_mm)
      riser_height_mm = rise_mm / counts[:total].to_f
      rise1_mm = riser_height_mm * counts[:first]
      second_direction = rotate_direction(direction, turn)

      model.start_operation('OpenSU: Create L Stair', true)
      begin
        stair = model.entities.add_group
        stair.name = name
        create_stair_flight(stair.entities, 'Flight01', origin_mm, direction, width_mm, run1_mm, counts[:first], riser_height_mm)

        first_end = advance_xy(origin_mm, direction, run1_mm)
        landing_top_z = origin_mm[2] + rise1_mm
        create_oriented_landing(stair.entities, 'Landing_001', first_end, direction, width_mm, landing_length_mm, landing_top_z, landing_thickness_mm)

        second_start = advance_xy(first_end, direction, landing_length_mm)
        second_start[2] = landing_top_z
        create_stair_flight(stair.entities, 'Flight02', second_start, second_direction, width_mm, run2_mm, counts[:second], riser_height_mm)
        end_mm = advance_xy(second_start, second_direction, run2_mm)
        end_mm[2] = end_elevation_mm

        annotate_architecture_entity(
          stair,
          'l_stair',
          origin_mm: origin_mm,
          end_mm: end_mm,
          direction: params['direction'] || 'x+',
          turn: params['turn'] || 'left',
          width_mm: width_mm,
          run1_mm: run1_mm,
          run2_mm: run2_mm,
          landing_length_mm: landing_length_mm,
          landing_thickness_mm: landing_thickness_mm,
          rise_mm: rise_mm,
          riser_count: counts[:total],
          first_flight_risers: counts[:first],
          second_flight_risers: counts[:second],
          riser_height_mm: riser_height_mm,
          level_name: level_name
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(stair, 'l_stair', {
        origin_mm: origin_mm,
        end_mm: end_mm,
        width_mm: width_mm,
        rise_mm: rise_mm,
        riser_count: counts[:total],
        riser_height_mm: riser_height_mm.round(3),
        level_name: level_name
      })
    end

    def create_u_stair(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      origin_mm = vector3_numbers(params['origin_mm'] || params['origin'], 'origin_mm')
      direction = direction_vector(params['direction'] || 'x+')
      turn = turn_sign(params['turn'] || 'left')
      width_mm = positive_number(params['width_mm'] || 1200, 'width_mm')
      gap_mm = finite_number(params.key?('gap_mm') ? params['gap_mm'] : 200, 'gap_mm')
      raise 'gap_mm must be 0 or greater.' if gap_mm.negative?
      run1_mm = positive_number(params['run1_mm'], 'run1_mm')
      run2_mm = positive_number(params['run2_mm'], 'run2_mm')
      landing_depth_mm = positive_number(params['landing_depth_mm'] || width_mm, 'landing_depth_mm')
      landing_thickness_mm = positive_number(params['landing_thickness_mm'] || 150, 'landing_thickness_mm')
      end_elevation_mm = finite_number(params['end_elevation_mm'], 'end_elevation_mm')
      level_name = normalized_name(params['level_name'])
      ensure_level_exists!(model, level_name) if level_name
      name = normalized_name(params['name']) || next_entity_name(model, 'UStair')

      rise_mm = end_elevation_mm - origin_mm[2]
      raise 'end_elevation_mm must be above stair origin.' unless rise_mm.positive?
      counts = split_stair_risers(rise_mm, params, run1_mm, run2_mm)
      riser_height_mm = rise_mm / counts[:total].to_f
      rise1_mm = riser_height_mm * counts[:first]
      normal = [-direction[1], direction[0]]
      lateral = turn * (width_mm + gap_mm)

      model.start_operation('OpenSU: Create U Stair', true)
      begin
        stair = model.entities.add_group
        stair.name = name
        create_stair_flight(stair.entities, 'Flight01', origin_mm, direction, width_mm, run1_mm, counts[:first], riser_height_mm)

        first_end = advance_xy(origin_mm, direction, run1_mm)
        landing_top_z = origin_mm[2] + rise1_mm
        create_u_landing(stair.entities, first_end, direction, normal, width_mm, gap_mm, turn, landing_depth_mm, landing_top_z, landing_thickness_mm)

        second_start = advance_xy(first_end, direction, landing_depth_mm)
        second_start[0] += normal[0] * lateral
        second_start[1] += normal[1] * lateral
        second_start[2] = landing_top_z
        second_direction = [-direction[0], -direction[1]]
        create_stair_flight(stair.entities, 'Flight02', second_start, second_direction, width_mm, run2_mm, counts[:second], riser_height_mm)
        end_mm = advance_xy(second_start, second_direction, run2_mm)
        end_mm[2] = end_elevation_mm

        annotate_architecture_entity(
          stair,
          'u_stair',
          origin_mm: origin_mm,
          end_mm: end_mm,
          direction: params['direction'] || 'x+',
          turn: params['turn'] || 'left',
          width_mm: width_mm,
          gap_mm: gap_mm,
          run1_mm: run1_mm,
          run2_mm: run2_mm,
          landing_depth_mm: landing_depth_mm,
          landing_thickness_mm: landing_thickness_mm,
          rise_mm: rise_mm,
          riser_count: counts[:total],
          first_flight_risers: counts[:first],
          second_flight_risers: counts[:second],
          riser_height_mm: riser_height_mm,
          level_name: level_name
        )
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      architecture_entity_result(stair, 'u_stair', {
        origin_mm: origin_mm,
        end_mm: end_mm,
        width_mm: width_mm,
        gap_mm: gap_mm,
        rise_mm: rise_mm,
        riser_count: counts[:total],
        riser_height_mm: riser_height_mm.round(3),
        level_name: level_name
      })
    end

    def slab_geometry_contract(target, type)
      origin_mm = parse_vector_attribute(target, 'origin_mm')
      width_mm = positive_number(target.get_attribute('OpenSU', 'width_mm'), 'stored slab width')
      depth_mm = positive_number(target.get_attribute('OpenSU', 'depth_mm'), 'stored slab depth')
      if type == 'flat_roof'
        thickness_mm = positive_number(target.get_attribute('OpenSU', 'slab_thickness_mm'), 'stored roof slab thickness')
        geometry_group = target.entities.grep(Sketchup::Group).find { |group| group.name.to_s == 'Roof_Slab' }
        raise 'Flat roof is missing Roof_Slab geometry.' unless geometry_group
      else
        thickness_mm = positive_number(target.get_attribute('OpenSU', 'thickness_mm'), 'stored slab thickness')
        geometry_group = target
      end
      [origin_mm, width_mm, depth_mm, thickness_mm, geometry_group]
    end

    def parse_vector_attribute(entity, key)
      raw = entity.get_attribute('OpenSU', key)
      parsed = JSON.parse(raw.to_s)
      vector3_numbers(parsed, "stored #{key}")
    rescue JSON::ParserError
      raise "Stored #{key} is invalid."
    end

    def parse_openings_attribute(entity, key)
      raw = entity.get_attribute('OpenSU', key)
      return [] if raw.nil? || raw.to_s.strip.empty?
      parsed = JSON.parse(raw.to_s)
      raise "Stored #{key} must be an array." unless parsed.is_a?(Array)
      parsed
    rescue JSON::ParserError
      raise "Stored #{key} is invalid."
    end

    def next_slab_opening_name(entity)
      openings = parse_openings_attribute(entity, 'slab_openings_json')
      existing = openings.map { |opening| opening['name'].to_s }
      index = 1
      loop do
        candidate = format('SlabOpening_%03d', index)
        return candidate unless existing.include?(candidate)
        index += 1
      end
    end

    def slab_openings_overlap?(a, b)
      ax0 = a['offset_x_mm'].to_f
      ay0 = a['offset_y_mm'].to_f
      ax1 = ax0 + a['width_mm'].to_f
      ay1 = ay0 + a['depth_mm'].to_f
      bx0 = b[:offset_x_mm].to_f
      by0 = b[:offset_y_mm].to_f
      bx1 = bx0 + b[:width_mm].to_f
      by1 = by0 + b[:depth_mm].to_f
      ax0 < bx1 && ax1 > bx0 && ay0 < by1 && ay1 > by0
    end

    def build_axis_slab_shell(entities, origin_mm, width_mm, depth_mm, thickness_mm, openings)
      xs = [0.0, width_mm.to_f]
      ys = [0.0, depth_mm.to_f]
      openings.each do |opening|
        xs << opening['offset_x_mm'].to_f
        xs << opening['offset_x_mm'].to_f + opening['width_mm'].to_f
        ys << opening['offset_y_mm'].to_f
        ys << opening['offset_y_mm'].to_f + opening['depth_mm'].to_f
      end
      xs = xs.uniq.sort
      ys = ys.uniq.sort
      occupied = {}

      (0...(xs.length - 1)).each do |ix|
        (0...(ys.length - 1)).each do |iy|
          cx = (xs[ix] + xs[ix + 1]) / 2.0
          cy = (ys[iy] + ys[iy + 1]) / 2.0
          inside_hole = openings.any? do |opening|
            ox0 = opening['offset_x_mm'].to_f
            oy0 = opening['offset_y_mm'].to_f
            ox1 = ox0 + opening['width_mm'].to_f
            oy1 = oy0 + opening['depth_mm'].to_f
            cx > ox0 && cx < ox1 && cy > oy0 && cy < oy1
          end
          occupied[[ix, iy]] = !inside_hole
        end
      end

      point = lambda do |x, y, z|
        [mm(origin_mm[0] + x), mm(origin_mm[1] + y), mm(origin_mm[2] + z)]
      end

      occupied.each do |(ix, iy), filled|
        next unless filled
        x0 = xs[ix]
        x1 = xs[ix + 1]
        y0 = ys[iy]
        y1 = ys[iy + 1]
        add_shell_face(entities, [point.call(x0, y0, 0), point.call(x0, y1, 0), point.call(x1, y1, 0), point.call(x1, y0, 0)])
        add_shell_face(entities, [point.call(x0, y0, thickness_mm), point.call(x1, y0, thickness_mm), point.call(x1, y1, thickness_mm), point.call(x0, y1, thickness_mm)])

        add_shell_face(entities, [point.call(x0, y0, 0), point.call(x1, y0, 0), point.call(x1, y0, thickness_mm), point.call(x0, y0, thickness_mm)]) unless occupied[[ix, iy - 1]]
        add_shell_face(entities, [point.call(x1, y0, 0), point.call(x1, y1, 0), point.call(x1, y1, thickness_mm), point.call(x1, y0, thickness_mm)]) unless occupied[[ix + 1, iy]]
        add_shell_face(entities, [point.call(x1, y1, 0), point.call(x0, y1, 0), point.call(x0, y1, thickness_mm), point.call(x1, y1, thickness_mm)]) unless occupied[[ix, iy + 1]]
        add_shell_face(entities, [point.call(x0, y1, 0), point.call(x0, y0, 0), point.call(x0, y0, thickness_mm), point.call(x0, y1, thickness_mm)]) unless occupied[[ix - 1, iy]]
      end
    end

    def add_shell_face(entities, points)
      face = entities.add_face(points)
      raise 'SketchUp could not create slab shell face.' unless face
      face
    end

    def polygon_points(value)
      raise 'points_mm must contain at least 3 [x,y,z] vertices.' unless value.is_a?(Array) && value.length >= 3
      points = value.map.with_index { |point, index| vector3_numbers(point, "points_mm[#{index}]") }
      z = points.first[2]
      raise 'All polygon vertices must share the same Z elevation.' unless points.all? { |point| (point[2] - z).abs < 0.001 }
      raise 'Polygon area is too small.' if polygon_signed_area(points).abs < 1.0
      raise 'Polygon outline self-intersects.' if polygon_self_intersects?(points)
      points
    end

    def polygon_signed_area(points)
      sum = 0.0
      points.each_with_index do |point, index|
        nxt = points[(index + 1) % points.length]
        sum += (point[0] * nxt[1]) - (nxt[0] * point[1])
      end
      sum / 2.0
    end

    def polygon_self_intersects?(points)
      edges = points.each_index.map { |index| [points[index], points[(index + 1) % points.length], index] }
      edges.combination(2).any? do |a, b|
        i = a[2]
        j = b[2]
        next false if i == j || ((i + 1) % points.length) == j || ((j + 1) % points.length) == i
        segments_intersect_2d?(a[0], a[1], b[0], b[1])
      end
    end

    def segments_intersect_2d?(a, b, c, d)
      o1 = orientation_2d(a, b, c)
      o2 = orientation_2d(a, b, d)
      o3 = orientation_2d(c, d, a)
      o4 = orientation_2d(c, d, b)
      (o1 * o2) < -1.0e-9 && (o3 * o4) < -1.0e-9
    end

    def orientation_2d(a, b, c)
      ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0]))
    end

    def build_polygon_prism(entities, points_mm, thickness_mm)
      points = points_mm.map { |point| point.map { |value| mm(value) } }
      face = entities.add_face(points)
      raise 'SketchUp could not create polygon face.' unless face
      face.reverse! if face.normal.z < 0
      face.pushpull(mm(thickness_mm))
      raise 'Polygon prism is not a closed manifold solid.' if entities.parent.respond_to?(:manifold?) && !entities.parent.manifold?
    end

    def direction_vector(value)
      case value.to_s.downcase
      when 'x+', '+x', 'east' then [1.0, 0.0]
      when 'x-', '-x', 'west' then [-1.0, 0.0]
      when 'y+', '+y', 'north' then [0.0, 1.0]
      when 'y-', '-y', 'south' then [0.0, -1.0]
      else
        raise 'direction must be x+, x-, y+, or y-.'
      end
    end

    def turn_sign(value)
      case value.to_s.downcase
      when 'left' then 1.0
      when 'right' then -1.0
      else
        raise 'turn must be left or right.'
      end
    end

    def rotate_direction(direction, turn)
      turn.positive? ? [-direction[1], direction[0]] : [direction[1], -direction[0]]
    end

    def advance_xy(point, direction, distance)
      [point[0] + (direction[0] * distance), point[1] + (direction[1] * distance), point[2]]
    end

    def split_stair_risers(rise_mm, params, run1_mm, run2_mm)
      total = if params.key?('riser_count') && !params['riser_count'].nil?
                integer_in_range(params['riser_count'], 'riser_count', 4, 100)
              else
                target = positive_number(params['target_riser_height_mm'] || 165, 'target_riser_height_mm')
                [[(rise_mm / target).round, 4].max, 100].min
              end
      riser_height = rise_mm / total.to_f
      raise 'Calculated riser height is outside 80-220 mm.' unless riser_height.between?(80.0, 220.0)
      first = (total / 2.0).floor
      second = total - first
      raise 'Calculated first-flight tread depth is too small (< 150 mm).' if (run1_mm / first.to_f) < 150.0
      raise 'Calculated second-flight tread depth is too small (< 150 mm).' if (run2_mm / second.to_f) < 150.0
      { total: total, first: first, second: second }
    end

    def create_stair_flight(parent_entities, prefix, start_mm, direction, width_mm, run_mm, riser_count, riser_height_mm)
      normal = [-direction[1], direction[0]]
      half = width_mm / 2.0
      tread = run_mm / riser_count.to_f
      riser_count.times do |index|
        along0 = tread * index
        along1 = tread * (index + 1)
        step = parent_entities.add_group
        step.name = format('%s_Step_%03d', prefix, index + 1)
        p0 = advance_xy(start_mm, direction, along0)
        p1 = advance_xy(start_mm, direction, along1)
        footprint = [
          [mm(p0[0] - normal[0] * half), mm(p0[1] - normal[1] * half), mm(start_mm[2])],
          [mm(p1[0] - normal[0] * half), mm(p1[1] - normal[1] * half), mm(start_mm[2])],
          [mm(p1[0] + normal[0] * half), mm(p1[1] + normal[1] * half), mm(start_mm[2])],
          [mm(p0[0] + normal[0] * half), mm(p0[1] + normal[1] * half), mm(start_mm[2])]
        ]
        add_closed_prism(step.entities, footprint, mm(riser_height_mm * (index + 1)))
      end
    end

    def create_oriented_landing(parent_entities, name, start_edge_center, direction, width_mm, length_mm, top_z_mm, thickness_mm)
      normal = [-direction[1], direction[0]]
      half = width_mm / 2.0
      z0 = top_z_mm - thickness_mm
      a = [start_edge_center[0] - normal[0] * half, start_edge_center[1] - normal[1] * half, z0]
      b = [start_edge_center[0] + direction[0] * length_mm - normal[0] * half, start_edge_center[1] + direction[1] * length_mm - normal[1] * half, z0]
      c = [start_edge_center[0] + direction[0] * length_mm + normal[0] * half, start_edge_center[1] + direction[1] * length_mm + normal[1] * half, z0]
      d = [start_edge_center[0] + normal[0] * half, start_edge_center[1] + normal[1] * half, z0]
      landing = parent_entities.add_group
      landing.name = name
      add_closed_prism(landing.entities, [a, b, c, d].map { |point| point.map { |value| mm(value) } }, mm(thickness_mm))
      landing
    end

    def create_u_landing(parent_entities, first_end, direction, normal, width_mm, gap_mm, turn, depth_mm, top_z_mm, thickness_mm)
      flight2_center = turn * (width_mm + gap_mm)
      min_side = [(-width_mm / 2.0), flight2_center - (width_mm / 2.0)].min
      max_side = [(width_mm / 2.0), flight2_center + (width_mm / 2.0)].max
      z0 = top_z_mm - thickness_mm
      points = [
        [first_end[0] + normal[0] * min_side, first_end[1] + normal[1] * min_side, z0],
        [first_end[0] + direction[0] * depth_mm + normal[0] * min_side, first_end[1] + direction[1] * depth_mm + normal[1] * min_side, z0],
        [first_end[0] + direction[0] * depth_mm + normal[0] * max_side, first_end[1] + direction[1] * depth_mm + normal[1] * max_side, z0],
        [first_end[0] + normal[0] * max_side, first_end[1] + normal[1] * max_side, z0]
      ]
      landing = parent_entities.add_group
      landing.name = 'Landing_001'
      add_closed_prism(landing.entities, points.map { |point| point.map { |value| mm(value) } }, mm(thickness_mm))
      landing
    end
  end
end

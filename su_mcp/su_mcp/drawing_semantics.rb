# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    DRAWING_SEMANTIC_TOOL_NAMES = %w[
      define_grid
      define_space
    ].freeze unless const_defined?(:DRAWING_SEMANTIC_TOOL_NAMES, false)

    unless private_method_defined?(:handle_tool_call_without_drawing_semantics)
      alias_method :handle_tool_call_without_drawing_semantics, :handle_tool_call
      private :handle_tool_call_without_drawing_semantics
    end

    unless private_method_defined?(:inspect_model_without_drawing_semantics)
      alias_method :inspect_model_without_drawing_semantics, :inspect_model
      private :inspect_model_without_drawing_semantics
    end

    private

    def handle_tool_call(request)
      tool_name = request.dig('params', 'name')
      return handle_tool_call_without_drawing_semantics(request) unless DRAWING_SEMANTIC_TOOL_NAMES.include?(tool_name)

      args = request.dig('params', 'arguments') || {}
      architecture_tool_response(request) do
        case tool_name
        when 'define_grid'
          define_grid(args)
        when 'define_space'
          define_space(args)
        else
          raise "Unknown drawing semantic tool: #{tool_name}"
        end
      end
    end

    def inspect_model(params)
      result = inspect_model_without_drawing_semantics(params)
      model = Sketchup.active_model
      result[:grids] = parse_model_semantic_array(model, 'grids_json')
      result[:spaces] = parse_model_semantic_array(model, 'spaces_json')
      result[:semantic_summary] = {
        grids: result[:grids].length,
        spaces: result[:spaces].length,
        space_area_m2: result[:spaces].sum { |space| space['area_m2'].to_f }.round(3)
      }
      result
    end

    def define_grid(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      name = normalized_name(params['name'])
      raise 'name is required.' unless name
      axis = params['axis'].to_s.downcase
      raise "axis must be 'x' or 'y'." unless %w[x y].include?(axis)
      coordinate_mm = finite_number(params['coordinate_mm'], 'coordinate_mm')
      source_ref = normalized_name(params['source_ref'])

      grids = parse_model_semantic_array(model, 'grids_json')
      if grids.any? { |grid| grid['name'].to_s.casecmp?(name) }
        raise "A grid named #{name.inspect} already exists."
      end
      if grids.any? { |grid| grid['axis'].to_s == axis && (grid['coordinate_mm'].to_f - coordinate_mm).abs < 0.001 }
        raise "A #{axis.upcase}-axis grid already exists at #{coordinate_mm} mm."
      end

      grid = {
        name: name,
        axis: axis,
        coordinate_mm: coordinate_mm,
        source_ref: source_ref
      }.compact

      model.start_operation('OpenSU: Define Grid', true)
      begin
        grids << JSON.parse(JSON.generate(grid))
        grids.sort_by! { |item| [item['axis'].to_s, item['coordinate_mm'].to_f] }
        model.set_attribute('OpenSU', 'grids_json', JSON.generate(grids))
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        type: 'grid',
        protocol_unit: 'mm',
        grid: grid,
        grids: grids
      }
    end

    def define_space(params)
      model = Sketchup.active_model
      raise 'No active SketchUp model.' unless model

      name = normalized_name(params['name'])
      raise 'name is required.' unless name
      level_name = normalized_name(params['level_name'])
      raise 'level_name is required.' unless level_name
      ensure_level_exists!(model, level_name)

      boundary = params['boundary_mm']
      unless boundary.is_a?(Array) && boundary.length >= 3
        raise 'boundary_mm must contain at least three [x,y] points.'
      end
      points = boundary.each_with_index.map do |point, index|
        unless point.is_a?(Array) && point.length == 2
          raise "boundary_mm[#{index}] must be [x,y]."
        end
        [finite_number(point[0], "boundary_mm[#{index}][0]"), finite_number(point[1], "boundary_mm[#{index}][1]")]
      end
      raise 'Space boundary has zero area.' if polygon_area_mm2(points).abs < 1.0
      raise 'Space boundary self-intersects.' if polygon_self_intersects?(points)

      program_type = normalized_name(params['program_type']) || 'other'
      department = normalized_name(params['department'])
      zone = normalized_name(params['zone'])
      source_ref = normalized_name(params['source_ref'])
      area_m2 = (polygon_area_mm2(points).abs / 1_000_000.0).round(3)

      spaces = parse_model_semantic_array(model, 'spaces_json')
      if spaces.any? { |space| space['name'].to_s.casecmp?(name) }
        raise "A space named #{name.inspect} already exists."
      end

      space = {
        name: name,
        level_name: level_name,
        boundary_mm: points,
        program_type: program_type,
        department: department,
        zone: zone,
        source_ref: source_ref,
        area_m2: area_m2
      }.compact

      model.start_operation('OpenSU: Define Space', true)
      begin
        spaces << JSON.parse(JSON.generate(space))
        spaces.sort_by! { |item| [item['level_name'].to_s, item['name'].to_s.downcase] }
        model.set_attribute('OpenSU', 'spaces_json', JSON.generate(spaces))
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      {
        type: 'space',
        protocol_unit: 'mm',
        space: space,
        spaces: spaces
      }
    end

    def parse_model_semantic_array(model, key)
      raw = model.get_attribute('OpenSU', key)
      return [] if raw.nil? || raw.to_s.strip.empty?

      parsed = JSON.parse(raw.to_s)
      parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError
      []
    end

    def polygon_area_mm2(points)
      sum = 0.0
      points.each_index do |index|
        x1, y1 = points[index]
        x2, y2 = points[(index + 1) % points.length]
        sum += (x1 * y2) - (x2 * y1)
      end
      sum / 2.0
    end

    def polygon_self_intersects?(points)
      segments = points.each_index.map do |index|
        [points[index], points[(index + 1) % points.length]]
      end
      segments.each_with_index do |segment_a, index_a|
        segments.each_with_index do |segment_b, index_b|
          next if index_b <= index_a
          next if (index_a - index_b).abs == 1
          next if index_a.zero? && index_b == segments.length - 1
          return true if segments_intersect_2d?(segment_a[0], segment_a[1], segment_b[0], segment_b[1])
        end
      end
      false
    end

    def segments_intersect_2d?(a, b, c, d)
      o1 = orientation_2d(a, b, c)
      o2 = orientation_2d(a, b, d)
      o3 = orientation_2d(c, d, a)
      o4 = orientation_2d(c, d, b)
      (o1 * o2).negative? && (o3 * o4).negative?
    end

    def orientation_2d(a, b, c)
      ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0]))
    end
  end
end

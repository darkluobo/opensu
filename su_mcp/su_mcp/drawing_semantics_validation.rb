# frozen_string_literal: true

module SU_MCP
  class Server
    unless private_method_defined?(:validate_model_without_drawing_semantics)
      alias_method :validate_model_without_drawing_semantics, :validate_model
      private :validate_model_without_drawing_semantics
    end

    private

    def validate_model(params)
      result = validate_model_without_drawing_semantics(params)
      model = Sketchup.active_model
      errors = result[:errors] || []
      warnings = result[:warnings] || []

      grids = parse_model_semantic_array(model, 'grids_json')
      spaces = parse_model_semantic_array(model, 'spaces_json')
      levels = parse_model_levels(model)
      level_names = levels.map { |level| level['name'].to_s }

      grid_names = {}
      grid_positions = {}
      grids.each_with_index do |grid, index|
        name = grid['name'].to_s.strip
        axis = grid['axis'].to_s
        coordinate = grid['coordinate_mm']
        errors << "Grid ##{index + 1} has no name." if name.empty?
        errors << "Grid #{name.inspect} has invalid axis #{axis.inspect}." unless %w[x y].include?(axis)
        unless coordinate.is_a?(Numeric) && coordinate.finite?
          errors << "Grid #{name.inspect} has invalid coordinate_mm."
          next
        end
        key = name.downcase
        errors << "Duplicate grid name #{name.inspect}." if grid_names.key?(key)
        grid_names[key] = true
        position_key = [axis, coordinate.to_f.round(3)]
        errors << "Duplicate #{axis.upcase}-axis grid coordinate #{coordinate} mm." if grid_positions.key?(position_key)
        grid_positions[position_key] = true
      end

      space_names = {}
      spaces.each_with_index do |space, index|
        name = space['name'].to_s.strip
        level_name = space['level_name'].to_s.strip
        boundary = space['boundary_mm']
        errors << "Space ##{index + 1} has no name." if name.empty?
        key = name.downcase
        errors << "Duplicate space name #{name.inspect}." if space_names.key?(key)
        space_names[key] = true
        errors << "Space #{name.inspect} references undefined level #{level_name.inspect}." unless level_names.include?(level_name)
        unless boundary.is_a?(Array) && boundary.length >= 3 && boundary.all? { |point| point.is_a?(Array) && point.length == 2 && point.all? { |value| value.is_a?(Numeric) && value.finite? } }
          errors << "Space #{name.inspect} has invalid boundary_mm."
          next
        end
        points = boundary.map { |point| [point[0].to_f, point[1].to_f] }
        area_m2 = polygon_area_mm2(points).abs / 1_000_000.0
        errors << "Space #{name.inspect} has zero area." if area_m2 < 0.000001
        errors << "Space #{name.inspect} boundary self-intersects." if polygon_self_intersects?(points)
        stored_area = space['area_m2']
        if stored_area.is_a?(Numeric) && (stored_area.to_f - area_m2).abs > 0.01
          warnings << "Space #{name.inspect} stored area differs from boundary area by more than 0.01 m2."
        end
      end

      result[:errors] = errors
      result[:warnings] = warnings
      result[:valid] = errors.empty?
      result[:summary] ||= {}
      result[:summary][:grids] = grids.length
      result[:summary][:spaces] = spaces.length
      result[:summary][:space_area_m2] = spaces.sum { |space| space['area_m2'].to_f }.round(3)
      result
    end
  end
end

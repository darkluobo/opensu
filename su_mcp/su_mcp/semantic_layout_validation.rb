# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    unless private_method_defined?(:validate_model_without_semantic_layout)
      alias_method :validate_model_without_semantic_layout, :validate_model
      private :validate_model_without_semantic_layout
    end

    private

    def validate_model(params)
      result = validate_model_without_semantic_layout(params)
      model = Sketchup.active_model
      errors = result[:errors] || []
      warnings = result[:warnings] || []
      grids = parse_model_semantic_array(model, 'grids_json')
      spaces = parse_model_semantic_array(model, 'spaces_json')
      levels = parse_model_levels(model)
      level_names = levels.map { |item| item['name'].to_s }
      grid_lookup = grids.each_with_object({}) { |item, memo| memo[[item['axis'].to_s, item['name'].to_s.downcase]] = item }
      space_lookup = spaces.each_with_object({}) { |item, memo| memo[item['name'].to_s.downcase] = item }

      checked = 0
      drift_warnings = 0
      model.entities.each do |entity|
        next unless entity.is_a?(Sketchup::Group)
        source = entity.get_attribute('OpenSU', 'layout_source').to_s
        next if source.empty?
        checked += 1
        name = entity.name.to_s

        case source
        when 'grid_intersection'
          x_name = entity.get_attribute('OpenSU', 'grid_x').to_s
          y_name = entity.get_attribute('OpenSU', 'grid_y').to_s
          level_name = entity.get_attribute('OpenSU', 'level_name').to_s
          x_grid = grid_lookup[['x', x_name.downcase]]
          y_grid = grid_lookup[['y', y_name.downcase]]
          errors << "#{name}: referenced X grid #{x_name.inspect} does not exist." unless x_grid
          errors << "#{name}: referenced Y grid #{y_name.inspect} does not exist." unless y_grid
          errors << "#{name}: referenced level #{level_name.inspect} does not exist." unless level_names.include?(level_name)
          center = parse_entity_json_attribute(entity, 'center_mm')
          if x_grid && y_grid && center.is_a?(Array) && center.length >= 2
            if (center[0].to_f - x_grid['coordinate_mm'].to_f).abs > 1.0 || (center[1].to_f - y_grid['coordinate_mm'].to_f).abs > 1.0
              warnings << "#{name}: stored column center no longer coincides with #{x_name}/#{y_name} grid intersection."
              drift_warnings += 1
            end
          end
        when 'grid_span'
          start_ref = entity.get_attribute('OpenSU', 'grid_start').to_s
          end_ref = entity.get_attribute('OpenSU', 'grid_end').to_s
          level_name = entity.get_attribute('OpenSU', 'level_name').to_s
          errors << "#{name}: referenced level #{level_name.inspect} does not exist." unless level_names.include?(level_name)
          start_grids = semantic_grid_ref_pair(grid_lookup, start_ref)
          end_grids = semantic_grid_ref_pair(grid_lookup, end_ref)
          errors << "#{name}: grid start reference #{start_ref.inspect} is invalid." unless start_grids
          errors << "#{name}: grid end reference #{end_ref.inspect} is invalid." unless end_grids
          start_mm = parse_entity_json_attribute(entity, 'start_mm')
          end_mm = parse_entity_json_attribute(entity, 'end_mm')
          if start_grids && start_mm.is_a?(Array) && start_mm.length >= 2 && semantic_xy_drift?(start_mm, start_grids)
            warnings << "#{name}: stored beam start no longer coincides with #{start_ref}."
            drift_warnings += 1
          end
          if end_grids && end_mm.is_a?(Array) && end_mm.length >= 2 && semantic_xy_drift?(end_mm, end_grids)
            warnings << "#{name}: stored beam end no longer coincides with #{end_ref}."
            drift_warnings += 1
          end
        when 'space_boundary'
          space_name = entity.get_attribute('OpenSU', 'space_name').to_s
          level_name = entity.get_attribute('OpenSU', 'level_name').to_s
          edge_index = entity.get_attribute('OpenSU', 'space_edge_index')
          space = space_lookup[space_name.downcase]
          errors << "#{name}: referenced Space #{space_name.inspect} does not exist." unless space
          errors << "#{name}: referenced level #{level_name.inspect} does not exist." unless level_names.include?(level_name)
          if space && edge_index.is_a?(Numeric)
            boundary = space['boundary_mm']
            index = edge_index.to_i
            if !boundary.is_a?(Array) || index.negative? || index >= boundary.length
              errors << "#{name}: referenced Space edge #{edge_index.inspect} is invalid."
            else
              start_mm = parse_entity_json_attribute(entity, 'start_mm')
              end_mm = parse_entity_json_attribute(entity, 'end_mm')
              expected_start = boundary[index]
              expected_end = boundary[(index + 1) % boundary.length]
              if start_mm.is_a?(Array) && end_mm.is_a?(Array) &&
                 (xy_distance_mm(start_mm, expected_start) > 1.0 || xy_distance_mm(end_mm, expected_end) > 1.0)
                warnings << "#{name}: partition wall no longer follows Space #{space_name} edge #{index}."
                drift_warnings += 1
              end
            end
          end
        else
          warnings << "#{name}: unknown OpenSU layout_source #{source.inspect}."
        end
      end

      result[:errors] = errors
      result[:warnings] = warnings
      result[:valid] = errors.empty?
      result[:summary] ||= {}
      result[:summary][:semantic_layout_entities] = checked
      result[:summary][:semantic_layout_drift_warnings] = drift_warnings
      result
    end

    def parse_entity_json_attribute(entity, key)
      raw = entity.get_attribute('OpenSU', key)
      return raw if raw.is_a?(Array) || raw.is_a?(Hash)
      return nil if raw.nil? || raw.to_s.strip.empty?
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      nil
    end

    def semantic_grid_ref_pair(grid_lookup, reference)
      parts = reference.to_s.split('/', 2).map(&:strip)
      return nil unless parts.length == 2 && parts.all? { |part| !part.empty? }
      x_grid = grid_lookup[['x', parts[0].downcase]]
      y_grid = grid_lookup[['y', parts[1].downcase]]
      return nil unless x_grid && y_grid
      [x_grid, y_grid]
    end

    def semantic_xy_drift?(point, grids)
      x_grid, y_grid = grids
      (point[0].to_f - x_grid['coordinate_mm'].to_f).abs > 1.0 ||
        (point[1].to_f - y_grid['coordinate_mm'].to_f).abs > 1.0
    end

    def xy_distance_mm(point_a, point_b)
      dx = point_a[0].to_f - point_b[0].to_f
      dy = point_a[1].to_f - point_b[1].to_f
      Math.sqrt((dx * dx) + (dy * dy))
    end
  end
end

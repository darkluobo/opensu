# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    unless private_method_defined?(:validate_model_without_phase3_building)
      alias_method :validate_model_without_phase3_building, :validate_model
      private :validate_model_without_phase3_building
    end

    private

    def validate_model(params)
      result = validate_model_without_phase3_building(params)
      model = Sketchup.active_model
      return result unless model

      max_entities = integer_in_range(params['max_entities'] || 1000, 'max_entities', 1, 5000)
      architecture = model.entities.to_a.select do |entity|
        entity.is_a?(Sketchup::Group) && entity.get_attribute('OpenSU', 'type')
      end.first(max_entities)

      supported = %w[ceiling stair flat_roof]
      result[:warnings] = result[:warnings].reject do |warning|
        supported.any? { |type| warning.include?("Unknown OpenSU architecture type '#{type}'") }
      end

      levels = validate_levels(model, result[:errors])
      level_names = levels.map { |level| level['name'].to_s }
      nested_non_manifold = 0

      architecture.each do |entity|
        type = entity.get_attribute('OpenSU', 'type').to_s
        label = entity.name.to_s.empty? ? entity.entityID : entity.name.to_s
        level_name = entity.get_attribute('OpenSU', 'level_name').to_s
        if !level_name.empty? && !level_names.include?(level_name)
          result[:errors] << "#{label} references undefined level #{level_name.inspect}."
        end

        case type
        when 'ceiling'
          validate_positive_attribute(entity, 'width_mm', result[:errors])
          validate_positive_attribute(entity, 'depth_mm', result[:errors])
          validate_positive_attribute(entity, 'thickness_mm', result[:errors])
          if entity.respond_to?(:manifold?) && !entity.manifold?
            result[:errors] << "#{label} is not a closed manifold solid."
            nested_non_manifold += 1
          end
        when 'stair'
          validate_positive_attribute(entity, 'width_mm', result[:errors])
          validate_positive_attribute(entity, 'run_mm', result[:errors])
          validate_positive_attribute(entity, 'rise_mm', result[:errors])
          validate_positive_attribute(entity, 'riser_height_mm', result[:errors])
          validate_positive_attribute(entity, 'tread_depth_mm', result[:errors])
          riser_count = entity.get_attribute('OpenSU', 'riser_count').to_i
          result[:errors] << "#{label} has invalid riser_count." if riser_count < 2
          step_groups = entity.entities.grep(Sketchup::Group)
          result[:errors] << "#{label} has #{step_groups.length} step solids but metadata expects #{riser_count}." if riser_count >= 2 && step_groups.length != riser_count
          nested_non_manifold += validate_nested_solids(step_groups, label, result[:errors])
        when 'flat_roof'
          validate_positive_attribute(entity, 'width_mm', result[:errors])
          validate_positive_attribute(entity, 'depth_mm', result[:errors])
          validate_positive_attribute(entity, 'slab_thickness_mm', result[:errors])
          parapet_height = entity.get_attribute('OpenSU', 'parapet_height_mm')
          if parapet_height.nil? || parapet_height.to_f.negative?
            result[:errors] << "#{label} has invalid parapet_height_mm."
          end
          validate_positive_attribute(entity, 'parapet_thickness_mm', result[:errors]) if parapet_height && parapet_height.to_f.positive?
          child_groups = entity.entities.grep(Sketchup::Group)
          required_children = parapet_height && parapet_height.to_f.positive? ? 5 : 1
          result[:errors] << "#{label} is missing roof/parapet solids." if child_groups.length < required_children
          nested_non_manifold += validate_nested_solids(child_groups, label, result[:errors])
        end
      end

      result[:summary][:levels] = levels.length
      result[:summary][:ceilings] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'ceiling' }
      result[:summary][:stairs] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'stair' }
      result[:summary][:flat_roofs] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'flat_roof' }
      result[:summary][:phase3_non_manifold_solids] = nested_non_manifold
      result[:valid] = result[:errors].empty?
      result
    end

    def validate_levels(model, errors)
      raw = model.get_attribute('OpenSU', 'levels_json')
      return [] if raw.nil? || raw.to_s.strip.empty?

      levels = JSON.parse(raw.to_s)
      unless levels.is_a?(Array)
        errors << 'Model level metadata is not an array.'
        return []
      end

      names = []
      elevations = []
      levels.each_with_index do |level, index|
        unless level.is_a?(Hash)
          errors << "Level entry #{index + 1} is invalid."
          next
        end
        name = level['name'].to_s.strip
        errors << "Level entry #{index + 1} has no name." if name.empty?
        names << name unless name.empty?
        begin
          elevation = Float(level['elevation_mm'])
          errors << "Level #{name.empty? ? index + 1 : name} has non-finite elevation." unless elevation.finite?
          elevations << elevation if elevation.finite?
        rescue ArgumentError, TypeError
          errors << "Level #{name.empty? ? index + 1 : name} has invalid elevation_mm."
        end
        if level.key?('floor_to_floor_mm') && !level['floor_to_floor_mm'].nil?
          begin
            value = Float(level['floor_to_floor_mm'])
            errors << "Level #{name} has invalid floor_to_floor_mm." unless value.finite? && value.positive?
          rescue ArgumentError, TypeError
            errors << "Level #{name} has invalid floor_to_floor_mm."
          end
        end
      end

      duplicate_names = names.group_by(&:itself).select { |_name, items| items.length > 1 }.keys
      errors << "Duplicate level names: #{duplicate_names.join(', ')}" unless duplicate_names.empty?
      duplicate_elevations = elevations.group_by { |value| value.round(3) }.select { |_value, items| items.length > 1 }.keys
      errors << "Duplicate level elevations: #{duplicate_elevations.join(', ')}" unless duplicate_elevations.empty?
      levels
    rescue JSON::ParserError
      errors << 'Model has invalid levels_json metadata.'
      []
    end

    def validate_nested_solids(groups, parent_label, errors)
      failures = 0
      groups.each do |group|
        next unless group.respond_to?(:manifold?)
        next if group.manifold?

        child_label = group.name.to_s.empty? ? group.entityID : group.name.to_s
        errors << "#{parent_label}/#{child_label} is not a closed manifold solid."
        failures += 1
      end
      failures
    end
  end
end

# frozen_string_literal: true

module SU_MCP
  class Server
    unless private_method_defined?(:validate_model_without_building_elements)
      alias_method :validate_model_without_building_elements, :validate_model
      private :validate_model_without_building_elements
    end

    private

    def validate_model(params)
      result = validate_model_without_building_elements(params)
      model = Sketchup.active_model
      return result unless model

      max_entities = integer_in_range(params['max_entities'] || 1000, 'max_entities', 1, 5000)
      architecture = model.entities.to_a.select do |entity|
        entity.is_a?(Sketchup::Group) && entity.get_attribute('OpenSU', 'type')
      end.first(max_entities)

      supported = %w[column beam door window]
      result[:warnings] = result[:warnings].reject do |warning|
        supported.any? { |type| warning.include?("Unknown OpenSU architecture type '#{type}'") }
      end

      architecture.each do |entity|
        type = entity.get_attribute('OpenSU', 'type').to_s
        label = entity.name.to_s.empty? ? entity.entityID : entity.name.to_s

        case type
        when 'column'
          validate_positive_attribute(entity, 'width_mm', result[:errors])
          validate_positive_attribute(entity, 'depth_mm', result[:errors])
          validate_positive_attribute(entity, 'height_mm', result[:errors])
        when 'beam'
          validate_positive_attribute(entity, 'length_mm', result[:errors])
          validate_positive_attribute(entity, 'width_mm', result[:errors])
          validate_positive_attribute(entity, 'height_mm', result[:errors])
        when 'door', 'window'
          wall_id = entity.get_attribute('OpenSU', 'wall_id')
          opening_name = entity.get_attribute('OpenSU', 'opening_name').to_s
          result[:errors] << "#{label} is missing wall linkage." if wall_id.nil?
          result[:errors] << "#{label} is missing opening linkage." if opening_name.empty?
          if wall_id
            wall = model.find_entity_by_id(wall_id.to_i)
            unless wall && wall.is_a?(Sketchup::Group) && wall.get_attribute('OpenSU', 'type') == 'wall'
              result[:errors] << "#{label} references a missing or invalid wall."
            end
          end
          result[:errors] << "#{label} has no assembly geometry." if entity.entities.empty?
        end
      end

      result[:summary][:columns] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'column' }
      result[:summary][:beams] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'beam' }
      result[:summary][:doors] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'door' }
      result[:summary][:windows] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'window' }
      result[:valid] = result[:errors].empty?
      result
    end
  end
end

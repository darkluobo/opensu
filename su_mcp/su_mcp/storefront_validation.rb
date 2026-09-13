# frozen_string_literal: true

module SU_MCP
  class Server
    unless private_method_defined?(:validate_model_without_storefront)
      alias_method :validate_model_without_storefront, :validate_model
      private :validate_model_without_storefront
    end

    private

    def validate_model(params)
      result = validate_model_without_storefront(params)
      model = Sketchup.active_model
      return result unless model

      max_entities = integer_in_range(params['max_entities'] || 1000, 'max_entities', 1, 5000)
      architecture = model.entities.to_a.select do |entity|
        entity.is_a?(Sketchup::Group) && entity.get_attribute('OpenSU', 'type')
      end.first(max_entities)

      result[:warnings] = result[:warnings].reject do |warning|
        warning.include?("Unknown OpenSU architecture type 'curtain_wall'")
      end

      total_openings = 0
      multi_opening_walls = 0
      architecture.each do |entity|
        type = entity.get_attribute('OpenSU', 'type').to_s
        label = entity.name.to_s.empty? ? entity.entityID : entity.name.to_s

        case type
        when 'wall'
          begin
            openings = parse_openings_or_empty(entity)
            total_openings += openings.length
            multi_opening_walls += 1 if openings.length > 1
            if openings.any?
              length_mm = positive_number(entity.get_attribute('OpenSU', 'length_mm'), 'stored wall length')
              height_mm = positive_number(entity.get_attribute('OpenSU', 'height_mm'), 'stored wall height')
              validate_opening_set!(openings, length_mm, height_mm)
            end
          rescue StandardError => e
            result[:errors] << "#{label} has invalid opening layout: #{e.message}"
          end
        when 'curtain_wall'
          validate_positive_attribute(entity, 'length_mm', result[:errors])
          validate_positive_attribute(entity, 'height_mm', result[:errors])
          validate_positive_attribute(entity, 'panel_width_mm', result[:errors])
          validate_positive_attribute(entity, 'row_height_mm', result[:errors])
          panel_count = entity.get_attribute('OpenSU', 'panel_count').to_i
          bay_count = entity.get_attribute('OpenSU', 'bay_count').to_i
          row_count = entity.get_attribute('OpenSU', 'row_count').to_i
          result[:errors] << "#{label} has no glass panels." unless panel_count.positive?
          result[:errors] << "#{label} has invalid bay metadata." unless bay_count.positive?
          result[:errors] << "#{label} has invalid row metadata." unless row_count.positive?
          result[:errors] << "#{label} has no assembly geometry." if entity.entities.empty?
        end
      end

      curtain_walls = architecture.select { |entity| entity.get_attribute('OpenSU', 'type') == 'curtain_wall' }
      result[:summary][:openings] = total_openings
      result[:summary][:multi_opening_walls] = multi_opening_walls
      result[:summary][:curtain_walls] = curtain_walls.length
      result[:summary][:curtain_glass_panels] = curtain_walls.sum { |entity| entity.get_attribute('OpenSU', 'panel_count').to_i }
      result[:valid] = result[:errors].empty?
      result
    end
  end
end

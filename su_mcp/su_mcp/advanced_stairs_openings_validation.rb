# frozen_string_literal: true

require 'json'

module SU_MCP
  class Server
    unless private_method_defined?(:validate_model_without_advanced_building)
      alias_method :validate_model_without_advanced_building, :validate_model
      private :validate_model_without_advanced_building
    end

    private

    def validate_model(params)
      result = validate_model_without_advanced_building(params)
      model = Sketchup.active_model
      return result unless model

      max_entities = integer_in_range(params['max_entities'] || 1000, 'max_entities', 1, 5000)
      architecture = model.entities.to_a.select do |entity|
        entity.is_a?(Sketchup::Group) && entity.get_attribute('OpenSU', 'type')
      end.first(max_entities)

      supported = %w[l_stair u_stair polygon_slab polygon_ceiling]
      result[:warnings] = result[:warnings].reject do |warning|
        supported.any? { |type| warning.include?("Unknown OpenSU architecture type '#{type}'") }
      end

      levels = parse_model_levels(model)
      level_names = levels.map { |level| level['name'].to_s }
      advanced_non_manifold = 0
      slab_openings = 0

      architecture.each do |entity|
        type = entity.get_attribute('OpenSU', 'type').to_s
        label = entity.name.to_s.empty? ? entity.entityID : entity.name.to_s
        level_name = entity.get_attribute('OpenSU', 'level_name').to_s
        if !level_name.empty? && !level_names.include?(level_name)
          result[:errors] << "#{label} references undefined level #{level_name.inspect}."
        end

        if %w[floor ceiling flat_roof].include?(type)
          slab_openings += validate_slab_openings(entity, type, label, result[:errors])
        end

        case type
        when 'polygon_slab', 'polygon_ceiling'
          validate_positive_attribute(entity, 'thickness_mm', result[:errors])
          vertex_count = entity.get_attribute('OpenSU', 'vertex_count').to_i
          result[:errors] << "#{label} has invalid vertex_count." if vertex_count < 3
          raw = entity.get_attribute('OpenSU', 'points_json')
          begin
            points = JSON.parse(raw.to_s)
            unless points.is_a?(Array) && points.length == vertex_count
              result[:errors] << "#{label} has inconsistent polygon point metadata."
            end
          rescue JSON::ParserError
            result[:errors] << "#{label} has invalid polygon point metadata."
          end
          if entity.respond_to?(:manifold?) && !entity.manifold?
            result[:errors] << "#{label} is not a closed manifold solid."
            advanced_non_manifold += 1
          end
        when 'l_stair', 'u_stair'
          validate_positive_attribute(entity, 'width_mm', result[:errors])
          validate_positive_attribute(entity, 'rise_mm', result[:errors])
          validate_positive_attribute(entity, 'run1_mm', result[:errors])
          validate_positive_attribute(entity, 'run2_mm', result[:errors])
          validate_positive_attribute(entity, 'riser_height_mm', result[:errors])
          riser_count = entity.get_attribute('OpenSU', 'riser_count').to_i
          first = entity.get_attribute('OpenSU', 'first_flight_risers').to_i
          second = entity.get_attribute('OpenSU', 'second_flight_risers').to_i
          result[:errors] << "#{label} has invalid riser_count." if riser_count < 4
          result[:errors] << "#{label} flight riser counts do not match total." unless first.positive? && second.positive? && (first + second == riser_count)
          children = entity.entities.grep(Sketchup::Group)
          expected = riser_count + 1
          result[:errors] << "#{label} has #{children.length} child solids but expects #{expected}." unless children.length == expected
          advanced_non_manifold += validate_nested_solids(children, label, result[:errors])
        end
      end

      result[:summary][:l_stairs] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'l_stair' }
      result[:summary][:u_stairs] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'u_stair' }
      result[:summary][:polygon_slabs] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'polygon_slab' }
      result[:summary][:polygon_ceilings] = architecture.count { |entity| entity.get_attribute('OpenSU', 'type') == 'polygon_ceiling' }
      result[:summary][:slab_openings] = slab_openings
      result[:summary][:advanced_non_manifold_solids] = advanced_non_manifold
      result[:valid] = result[:errors].empty?
      result
    end

    def validate_slab_openings(entity, type, label, errors)
      raw = entity.get_attribute('OpenSU', 'slab_openings_json')
      return 0 if raw.nil? || raw.to_s.strip.empty?

      openings = JSON.parse(raw.to_s)
      unless openings.is_a?(Array)
        errors << "#{label} slab opening metadata is not an array."
        return 0
      end

      width_mm = entity.get_attribute('OpenSU', 'width_mm').to_f
      depth_mm = entity.get_attribute('OpenSU', 'depth_mm').to_f
      names = []
      openings.each_with_index do |opening, index|
        unless opening.is_a?(Hash)
          errors << "#{label} slab opening #{index + 1} is invalid."
          next
        end
        name = opening['name'].to_s.strip
        errors << "#{label} slab opening #{index + 1} has no name." if name.empty?
        names << name unless name.empty?
        ox = opening['offset_x_mm'].to_f
        oy = opening['offset_y_mm'].to_f
        ow = opening['width_mm'].to_f
        od = opening['depth_mm'].to_f
        errors << "#{label}/#{name} has invalid opening width/depth." unless ow.positive? && od.positive?
        errors << "#{label}/#{name} touches or exceeds slab X boundary." unless ox.positive? && (ox + ow) < width_mm
        errors << "#{label}/#{name} touches or exceeds slab Y boundary." unless oy.positive? && (oy + od) < depth_mm
      end

      duplicate_names = names.group_by(&:itself).select { |_name, items| items.length > 1 }.keys
      errors << "#{label} has duplicate slab opening names: #{duplicate_names.join(', ')}" unless duplicate_names.empty?

      openings.each_with_index do |a, i|
        openings.each_with_index do |b, j|
          next unless j > i
          next unless opening_hashes_overlap?(a, b)
          errors << "#{label} slab openings #{a['name']} and #{b['name']} overlap."
        end
      end

      if type == 'flat_roof'
        slab = entity.entities.grep(Sketchup::Group).find { |group| group.name.to_s == 'Roof_Slab' }
        errors << "#{label} is missing Roof_Slab geometry." unless slab
      end
      openings.length
    rescue JSON::ParserError
      errors << "#{label} has invalid slab_openings_json metadata."
      0
    end

    def opening_hashes_overlap?(a, b)
      ax0 = a['offset_x_mm'].to_f
      ay0 = a['offset_y_mm'].to_f
      ax1 = ax0 + a['width_mm'].to_f
      ay1 = ay0 + a['depth_mm'].to_f
      bx0 = b['offset_x_mm'].to_f
      by0 = b['offset_y_mm'].to_f
      bx1 = bx0 + b['width_mm'].to_f
      by1 = by0 + b['depth_mm'].to_f
      ax0 < bx1 && ax1 > bx0 && ay0 < by1 && ay1 > by0
    end
  end
end

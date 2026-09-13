# frozen_string_literal: true

module SU_MCP
  class Server
    unless private_method_defined?(:validate_model_without_solid_checks)
      alias_method :validate_model_without_solid_checks, :validate_model
      private :validate_model_without_solid_checks
    end

    private

    def validate_model(params)
      result = validate_model_without_solid_checks(params)
      model = Sketchup.active_model
      return result unless model

      max_entities = integer_in_range(params['max_entities'] || 1000, 'max_entities', 1, 5000)
      architecture = model.entities.to_a.select do |entity|
        entity.is_a?(Sketchup::Group) && entity.get_attribute('OpenSU', 'type')
      end.first(max_entities)

      solid_types = %w[floor wall column beam]
      non_manifold = []
      architecture.each do |entity|
        type = entity.get_attribute('OpenSU', 'type').to_s
        next unless solid_types.include?(type)
        next unless entity.respond_to?(:manifold?)
        next if entity.manifold?

        label = entity.name.to_s.empty? ? entity.entityID : entity.name.to_s
        non_manifold << label
        result[:errors] << "#{label} is not a closed manifold solid."
      end

      result[:valid] = result[:errors].empty?
      result[:summary][:non_manifold_solids] = non_manifold.length
      result
    end
  end
end

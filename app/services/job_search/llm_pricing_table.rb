require "yaml"

module JobSearch
  # Tabela de preços por modelo.
  #
  # O provedor costuma responder com um snapshot datado do modelo pedido
  # (ex.: "gpt-5.6-2026-08-01"), então a busca aceita o nome exato ou o
  # maior prefixo cadastrado. Modelo sem preço completo -> nil: o custo
  # fica "desconhecido" em vez de inventado.
  class LlmPricingTable
    def self.load(path)
      data = File.exist?(path) ? YAML.safe_load_file(path) || {} : {}

      prices = data.each_with_object({}) do |(model, attributes), result|
        attributes = (attributes || {}).transform_keys(&:to_sym)
        next if attributes[:input_per_million].nil? || attributes[:output_per_million].nil?

        result[model.to_s] = LlmPricing.new(**attributes.slice(
          :input_per_million, :output_per_million, :cached_input_per_million
        ))
      end

      new(prices)
    end

    def initialize(prices = {})
      @prices = prices.transform_keys(&:to_s)
    end

    def for(model)
      return nil if model.nil?

      name = model.to_s
      return @prices[name] if @prices.key?(name)

      key = @prices.keys
                   .select { |candidate| name.start_with?("#{candidate}-") }
                   .max_by(&:length)

      key && @prices[key]
    end

    def cost_usd(model:, usage:)
      return nil unless usage

      self.for(model)&.cost_usd(usage)
    end
  end
end

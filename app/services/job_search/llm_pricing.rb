module JobSearch
  # Preço de um modelo, em USD por 1 milhão de tokens.
  #
  # Tokens de input em cache são cobrados pela tarifa de cache (se não
  # houver tarifa própria, pela tarifa normal de input). Tokens de
  # raciocínio já vêm somados em output_tokens.
  LlmPricing = Data.define(:input_per_million, :output_per_million, :cached_input_per_million) do
    def initialize(input_per_million:, output_per_million:, cached_input_per_million: nil)
      super(
        input_per_million: Float(input_per_million),
        output_per_million: Float(output_per_million),
        cached_input_per_million: Float(cached_input_per_million || input_per_million)
      )
    end

    def cost_usd(usage)
      uncached = usage.input_tokens - usage.cached_input_tokens

      total =
        (uncached * input_per_million) +
        (usage.cached_input_tokens * cached_input_per_million) +
        (usage.output_tokens * output_per_million)

      (total / 1_000_000.0).round(6)
    end
  end
end

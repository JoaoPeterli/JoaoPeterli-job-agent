module JobSearch
  # Orçamento de LLM de um run: limita tokens e custo acumulados.
  #
  # É checado ANTES de cada chamada (a chamada que estoura o limite já
  # foi paga; o que se evita é a próxima). O limite de custo só vale
  # quando o custo é conhecido: sem preço cadastrado, vale o de tokens.
  #
  # Um LlmBudget pertence a um único run (o Container cria um por agente).
  class LlmBudget
    attr_reader :calls, :total_tokens, :cost_usd

    def initialize(max_total_tokens:, max_cost_usd: nil)
      raise ArgumentError, "max_total_tokens must be positive" unless max_total_tokens.positive?
      raise ArgumentError, "max_cost_usd must be positive" if max_cost_usd && !max_cost_usd.positive?

      @max_total_tokens = max_total_tokens
      @max_cost_usd = max_cost_usd
      @calls = 0
      @total_tokens = 0
      @cost_usd = 0.0
    end

    def check!
      if @total_tokens >= @max_total_tokens
        raise LlmBudgetExceeded,
              "LLM token budget exceeded: #{@total_tokens}/#{@max_total_tokens} tokens"
      end

      return unless @max_cost_usd && @cost_usd >= @max_cost_usd

      raise LlmBudgetExceeded,
            format("LLM cost budget exceeded: $%<spent>.4f/$%<max>.4f", spent: @cost_usd, max: @max_cost_usd)
    end

    def record(usage:, cost_usd:)
      @calls += 1
      @total_tokens += usage.total_tokens if usage
      @cost_usd = (@cost_usd + cost_usd).round(6) if cost_usd
    end
  end
end

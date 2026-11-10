module JobSearch
  # O run gastou o orçamento de tokens/custo do LLM. Não é retryable:
  # tentar de novo só gastaria mais.
  class LlmBudgetExceeded < PlanningError
    def initialize(message)
      super(message, retryable: false)
    end
  end
end

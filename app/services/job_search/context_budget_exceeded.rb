module JobSearch
  # O prompt não cabe no orçamento de contexto. Não é retryable:
  # pedir um novo plano com o mesmo prompt não muda o tamanho dele.
  class ContextBudgetExceeded < PlanningError
    def initialize(message)
      super(message, retryable: false)
    end
  end
end

module JobSearch
  # A resposta do LLM violou o contrato (recusa, truncamento, falha).
  # Por padrão não é retryable: pedir de novo a mesma coisa tende a dar
  # o mesmo resultado.
  class LlmResponseError < PlanningError
    def initialize(message, retryable: false)
      super(message, retryable: retryable)
    end
  end
end

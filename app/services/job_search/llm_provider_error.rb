module JobSearch
  # Falha do provedor de LLM (credencial, permissão, limite, rede).
  #
  # Não é retryable pelo PlanningRetryPolicy: não é um plano ruim, então
  # não deve virar histórico, lição nem prompt de reparo. Retentativas
  # de rede/429/5xx já são feitas pelo próprio cliente HTTP do provedor.
  #
  # transient? indica se tentar mais tarde pode funcionar (útil para quem
  # agenda o agente, ex.: um job em fila).
  class LlmProviderError < PlanningError
    def initialize(message, transient:)
      super(message, retryable: false)
      @transient = transient
    end

    def transient?
      @transient
    end
  end
end

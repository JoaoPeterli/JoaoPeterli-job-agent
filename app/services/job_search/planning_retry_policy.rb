module JobSearch
  class PlanningRetryPolicy
    def initialize(max_attempts:)
      raise ArgumentError, "max_attempts must be positive" unless max_attempts.is_a?(Integer) && max_attempts.positive?

      @max_attempts = max_attempts
    end

    # memory: memória de curto prazo da execução. Cada plano rejeitado é
    # registrado nela, e as tentativas seguintes recebem o histórico para
    # não repetir erros que já foram corrigidos antes.
    #
    # lessons: lições de execuções anteriores, iguais em todas as tentativas.
    def call(objective:, memory: ShortTermMemory.new, lessons: [], inputs: [])
      attempt = 0
      previous_error = nil
      history = []

      begin
        attempt += 1

        context = PlanningContext.new(
          objective: objective,
          attempt: attempt,
          previous_error: previous_error,
          history: history.dup,
          lessons: lessons,
          inputs: inputs
        )

        yield(context)
      rescue PlanningError => error
        raise unless error.retryable?

        memory.record(
          :plan_rejected,
          "Attempt #{attempt}: #{rejection_reason(error)}"
        )

        raise if attempt >= @max_attempts

        history << rejection_entry(previous_error, attempt - 1) if previous_error
        previous_error = error
        retry
      end
    end

    private

    def rejection_reason(error)
      error.cause&.message || error.message
    end

    def rejection_entry(error, attempt)
      "Attempt #{attempt}: #{rejection_reason(error)}"
    end
  end
end

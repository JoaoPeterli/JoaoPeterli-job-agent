module JobSearch
  class PlanningContext
    attr_reader :objective,
                :attempt,
                :previous_error,
                :history

    # history: rejeições anteriores à última tentativa, em ordem.
    # A última fica em previous_error (seção de reparo do prompt), então
    # não é repetida aqui.
    def initialize(
      objective:,
      attempt: 1,
      previous_error: nil,
      history: []
    )
      @objective = objective
      @attempt = attempt
      @previous_error = previous_error
      @history = history.freeze
    end
  end
end

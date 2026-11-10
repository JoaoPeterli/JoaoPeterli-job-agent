module JobSearch
  class PlanningContext
    attr_reader :objective,
                :attempt,
                :previous_error,
                :history,
                :lessons

    # history: rejeições anteriores à última tentativa, em ordem.
    # A última fica em previous_error (seção de reparo do prompt), então
    # não é repetida aqui.
    #
    # lessons: lições recuperadas de execuções anteriores (outros run_id).
    def initialize(
      objective:,
      attempt: 1,
      previous_error: nil,
      history: [],
      lessons: []
    )
      @objective = objective
      @attempt = attempt
      @previous_error = previous_error
      @history = history.freeze
      @lessons = lessons.freeze
    end
  end
end

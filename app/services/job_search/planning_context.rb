module JobSearch
  class PlanningContext
    attr_reader :objective,
                :attempt,
                :previous_error,
                :history,
                :lessons,
                :inputs

    # history: rejeições anteriores à última tentativa, em ordem.
    # A última fica em previous_error (seção de reparo do prompt), então
    # não é repetida aqui.
    #
    # lessons: lições recuperadas de execuções anteriores (outros run_id).
    #
    # inputs: AgentInput recebidos de outros agentes (o planner usa só o
    # nome e a descrição).
    def initialize(
      objective:,
      attempt: 1,
      previous_error: nil,
      history: [],
      lessons: [],
      inputs: []
    )
      @inputs = inputs.freeze
      @objective = objective
      @attempt = attempt
      @previous_error = previous_error
      @history = history.freeze
      @lessons = lessons.freeze
    end
  end
end

module JobSearch
  class PlanningContext
    attr_reader :objective,
                :attempt,
                :previous_error

    def initialize(
      objective:,
      attempt: 1,
      previous_error: nil
    )
      @objective = objective
      @attempt = attempt
      @previous_error = previous_error
    end
  end
end

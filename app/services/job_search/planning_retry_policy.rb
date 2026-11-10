
module JobSearch
  class PlanningRetryPolicy
    def initialize(max_attempts:)
      raise ArgumentError, "max_attempts must be positive" unless max_attempts.is_a?(Integer) && max_attempts.positive?

      @max_attempts = max_attempts
    end

    def call(objective:)
      attempt = 0
      previous_error = nil

      begin
        attempt += 1

        context = PlanningContext.new(
          objective: objective,
          attempt: attempt,
          previous_error: previous_error
        )

        yield(context)
      rescue PlanningError => error
        raise unless error.retryable?
        raise if attempt >= @max_attempts

        previous_error = error
        retry
      end
    end
  end
end

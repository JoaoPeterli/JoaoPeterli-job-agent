module JobSearch
  class ExecutionReport
    def initialize(state:)
      @state = state
    end

    def to_h
      {
        objective: @state.objective,
        status: @state.status,
        steps: steps_report
      }
    end

    private

    def steps_report
      @state.step_states.each_with_object({}) do |(name, step_state), result|
        result[name] = {
          status: step_state.status,
          attempts: step_state.attempts,
          duration: step_state.duration,
          error: error_message(step_state)
        }
      end
    end

    def error_message(step_state)
      step_state.error&.message
    end
  end
end

module JobSearch
  class StepState
    attr_reader :status,
                :attempts,
                :observation,
                :error,
                :started_at,
                :finished_at

    def initialize(clock: Clock.new)
      @clock = clock

      @status = :pending
      @attempts = 0
      @observation = nil
      @error = nil
      @started_at = nil
      @finished_at = nil
    end

    def start!
      @status = :running
      @started_at = @clock.now
    end

    def add_observation(observation)
      @observation = observation
    end

    def complete!
      @status = :completed
      @finished_at = @clock.now
    end

    def fail!(error: nil)
      @status = :failed
      @error = error
      @finished_at = @clock.now
    end

    def record_attempt(attempt)
      @attempts = attempt
    end

    def duration
      return nil unless started_at
      return nil unless finished_at

      finished_at - started_at
    end
  end
end

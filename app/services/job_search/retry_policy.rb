
module JobSearch
  class RetryPolicy
    def initialize(max_attempts:, backoff_strategy:, sleeper:)
      raise ArgumentError, "max_attempts must be positive" unless max_attempts.positive?

      @max_attempts = max_attempts
      @backoff_strategy = backoff_strategy
      @sleeper = sleeper
    end

    def call(on_attempt: nil, max_attempts: @max_attempts)
      raise ArgumentError, "max_attempts must be positive" unless max_attempts.positive?

      # Uma chamada pode reduzir o limite configurado,
      # mas nunca ultrapassá-lo.
      effective_max_attempts = [ max_attempts, @max_attempts ].min

      attempts = 0

      begin
        attempts += 1
        on_attempt&.call(attempts)

        yield
      rescue TransientError
        raise if attempts >= effective_max_attempts

        delay = @backoff_strategy.delay_for(attempts)
        @sleeper.sleep(delay)

        retry
      end
    end
  end
end

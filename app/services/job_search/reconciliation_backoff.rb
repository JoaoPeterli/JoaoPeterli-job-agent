
module JobSearch
  class ReconciliationBackoff
    def initialize(base_delay: 30, max_delay: 300)
      raise ArgumentError, "base_delay must be positive" unless base_delay.positive?
      raise ArgumentError, "max_delay must be positive" unless max_delay.positive?
      raise ArgumentError, "max_delay must be >= base_delay" if max_delay < base_delay

      @base_delay = base_delay
      @max_delay = max_delay
    end

    def delay_for(attempt)
      raise ArgumentError, "attempt must be positive" unless attempt.is_a?(Integer) && attempt.positive?

      exponent = attempt - 1

      [ @base_delay * (2**exponent), @max_delay ].min
    end
  end
end

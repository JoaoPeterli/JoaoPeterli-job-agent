module JobSearch
  class BackoffStrategy
    def initialize(base_delay:)
      @base_delay = base_delay
    end

    def delay_for(attempt)
      @base_delay * (2 ** (attempt - 1))
    end
  end
end

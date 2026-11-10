
module JobSearch
  class PlanningError < StandardError
    attr_reader :cause

    def initialize(
      message,
      cause: nil,
      retryable: true
    )
      super(message)

      @cause = cause
      @retryable = retryable
    end

    def retryable?
      @retryable
    end
  end
end

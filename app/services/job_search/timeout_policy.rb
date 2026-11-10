require "timeout"

module JobSearch
  class TimeoutPolicy
    def initialize(timeout_seconds:)
      @timeout_seconds = timeout_seconds
    end

    def call
      Timeout.timeout(
        @timeout_seconds
      ) do
        yield
      end
    rescue Timeout::Error
      raise ToolTimeoutError,
            "Tool execution exceeded timeout of #{@timeout_seconds} seconds"
    end
  end
end

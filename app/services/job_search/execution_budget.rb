module JobSearch
  class ExecutionBudget
    attr_reader :tool_calls

    def initialize(
      max_steps:,
      max_tool_calls: nil,
      max_execution_seconds: nil,
      clock: Clock.new
    )
      @max_steps = max_steps
      @max_tool_calls = max_tool_calls
      @max_execution_seconds = max_execution_seconds
      @clock = clock
      @tool_calls = 0
      @started_at = @clock.now
    end

    # Reinicia a contagem para uma nova execução. Chamado pelo
    # PlanExecutor no início de cada plano.
    def start!
      @tool_calls = 0
      @started_at = @clock.now

      self
    end

    def validate!(plan:)
      validate_step_limit!(
        plan
      )

      true
    end

    def consume_tool_call!
      @tool_calls += 1

      validate_tool_call_limit!

      @tool_calls
    end

    def validate_execution_time!
      return true if @max_execution_seconds.nil?

      elapsed = @clock.now - @started_at

      if elapsed > @max_execution_seconds
        raise ExecutionBudgetExceeded,
              "Execution exceeds maximum execution time: #{elapsed} > #{@max_execution_seconds}"
      end

      true
    end

    private

    def validate_step_limit!(plan)
      step_count = plan.steps.length

      return if step_count <= @max_steps

      raise ExecutionBudgetExceeded,
            "Plan exceeds maximum number of steps: #{step_count} > #{@max_steps}"
    end

    def validate_tool_call_limit!
      return if @max_tool_calls.nil?
      return if @tool_calls <= @max_tool_calls

      raise ExecutionBudgetExceeded,
            "Execution exceeds maximum number of tool calls: #{@tool_calls} > #{@max_tool_calls}"
    end
  end
end

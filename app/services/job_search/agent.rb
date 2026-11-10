module JobSearch
  class Agent
    attr_reader :objective

    def initialize(
      objective:,
      planner:,
      plan_executor:,
      planning_retry_policy:
    )
      @objective = objective
      @planner = planner
      @plan_executor = plan_executor
      @planning_retry_policy = planning_retry_policy
    end

    def run
      state = AgentState.new(
        objective: objective
      )

      plan = @planning_retry_policy.call(
        objective: objective
      ) do |context|
        @planner.plan(context: context)
      end

      @plan_executor.execute(
        plan: plan,
        state: state
      )

      state
    end
  end
end


require "openai"

module JobSearch
  class Container
    def agent(objective:)
      Agent.new(
        objective: objective,
        planner: planner,
        plan_executor: plan_executor,
        planning_retry_policy: planning_retry_policy
      )
    end

    # Cada PlanExecutor tem o próprio budget, compartilhado apenas com o
    # seu Executor: execuções diferentes não somam tempo nem chamadas.
    def plan_executor
      budget = execution_budget

      PlanExecutor.new(
        executor: executor(execution_budget: budget),
        execution_budget: budget,
        tool_catalog: tool_catalog
      )
    end

    private

    def execution_budget
      ExecutionBudget.new(
        max_steps: 10,
        max_tool_calls: 20,
        max_execution_seconds: 30
      )
    end

    def timeout_policy
      @timeout_policy ||= TimeoutPolicy.new(
        timeout_seconds: 5
      )
    end

    def idempotency_store
      @idempotency_store ||= IdempotencyStore.new
    end

    def idempotency_policy
      @idempotency_policy ||= IdempotencyPolicy.new(
        store: idempotency_store
      )
    end

    def planner
      LlmPlanner.new(
        llm_client: llm_client,
        registry: registry,
        tool_catalog: tool_catalog,
        tool_validator: tool_validator,
        context_window: context_window
      )
    end

    def context_window
      ContextWindow.new(
        max_input_tokens: 8_000
      )
    end

    def planning_retry_policy
      PlanningRetryPolicy.new(
        max_attempts: 3
      )
    end

    def llm_client
      OpenAiLlmClient.new(
        client: openai_client,
        model: "gpt-5.6",
        output_schema: plan_output_schema,
        max_output_tokens: 2_000
      )
    end

    def plan_output_schema
      PlanOutputSchema.new(
        tool_catalog: tool_catalog
      ).to_h
    end

    def openai_client
      OpenAI::Client.new
    end

    def tool_catalog
      @tool_catalog ||= ToolCatalog.new(
        definitions: [
          search_jobs_definition,
          candidate_profile_definition,
          analyze_jobs_definition
        ]
      )
    end

    def search_jobs_definition
      ToolDefinition.new(
        name: :search_jobs,
        description: "Search for job opportunities",
        side_effects: false,
        arguments: {
          technology: "String - technology only, for example 'Ruby', 'Ruby on Rails', 'Node.js'. Do not include seniority, job title or remote status.",
          remote: "Boolean - whether the job must be remote"
        },
        schema: {
          technology: String,
          remote: [
            TrueClass,
            FalseClass
          ]
        }
      )
    end

    def candidate_profile_definition
      ToolDefinition.new(
        name: :candidate_profile,
        description: "Returns the candidate professional profile",
        side_effects: false,
        arguments: {},
        schema: {}
      )
    end

    def analyze_jobs_definition
      ToolDefinition.new(
        name: :analyze_jobs,
        description: "Analyzes jobs against the candidate profile",
        side_effects: false,
        arguments: {
          jobs: "Reference to the result of the job search step",
          profile: "Reference to the result of the candidate profile step"
        },
        schema: {
          jobs: Array,
          profile: Hash
        },
        planning_schema: {
          jobs: ObservationReference,
          profile: ObservationReference
        }
      )
    end

    def executor(execution_budget:)
      Executor.new(
        registry: registry,
        retry_policy: retry_policy,
        tool_catalog: tool_catalog,
        tool_validator: tool_validator,
        execution_budget: execution_budget,
        timeout_policy: timeout_policy,
        idempotency_policy: idempotency_policy
      )
    end

    def tool_validator
      ToolValidator.new
    end

    def retry_policy
      RetryPolicy.new(
        max_attempts: 3,
        backoff_strategy: backoff_strategy,
        sleeper: sleeper
      )
    end

    def backoff_strategy
      BackoffStrategy.new(
        base_delay: 1
      )
    end

    def sleeper
      Sleeper.new
    end

    def registry
      @registry ||= begin
        registry = ToolRegistry.new

        registry.register(
          :search_jobs,
          SearchJobsTool
        )

        registry.register(
          :candidate_profile,
          CandidateProfileTool
        )

        registry.register(
          :analyze_jobs,
          AnalyzeJobsTool
        )

        registry
      end
    end
  end
end

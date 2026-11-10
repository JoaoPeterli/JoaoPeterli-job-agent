
require "openai"

module JobSearch
  class Container
    # Ferramentas que este agente pode usar. Uma ferramenta registrada
    # fora desta lista não aparece para o LLM nem pode ser executada.
    ALLOWED_TOOLS = [
      :search_jobs,
      :candidate_profile,
      :analyze_jobs
    ].freeze

    MAX_CALLS_PER_TOOL = {
      search_jobs: 5
    }.freeze

    LLM_MODEL = "gpt-5.6".freeze
    LLM_PRICING_PATH = Rails.root.join("config/llm_pricing.yml")

    # Orçamento de LLM por run. 3 tentativas x (8k input + 2k output) já
    # cabem em 30k; o limite existe para que um laço futuro (ex.: agentes
    # delegando entre si) não gaste sem teto.
    MAX_LLM_TOKENS_PER_RUN = 30_000
    MAX_LLM_COST_USD_PER_RUN = 0.50

    # llm_client: permite trocar o LLM (ex.: cliente roteirizado nos testes
    # de integração) mantendo todo o resto da montagem real.
    #
    # event_logger: destino dos logs estruturados (padrão: Rails.logger).
    def initialize(llm_client: nil, event_logger: Observability::EventLogger.new)
      @llm_client = llm_client
      @event_logger = event_logger
    end

    # Cada agente recebe um Tracer próprio, compartilhado entre planner e
    # executor, para que todos os spans do run fiquem no mesmo trace.
    # O RunMetrics escuta esse Tracer e resume o run em "run.metrics";
    # o LLM é medido por um MeteredLlmClient com orçamento próprio do run.
    def agent(objective:)
      tracer = Observability::Tracer.new(
        event_logger: @event_logger,
        listeners: [ Observability::RunMetrics.new(event_logger: @event_logger) ]
      )

      Agent.new(
        objective: objective,
        planner: planner(tracer: tracer, client: metered_llm_client(tracer: tracer)),
        plan_executor: plan_executor(tracer: tracer),
        planning_retry_policy: planning_retry_policy,
        tracer: tracer,
        memory_store: memory_store,
        memory_retriever: memory_retriever
      )
    end

    # Cada PlanExecutor tem o próprio budget, compartilhado apenas com o
    # seu Executor: execuções diferentes não somam tempo nem chamadas.
    def plan_executor(tracer: Observability::NullTracer.new)
      budget = execution_budget

      PlanExecutor.new(
        executor: executor(execution_budget: budget),
        execution_budget: budget,
        tool_catalog: tool_catalog,
        tool_authorizer: tool_authorizer,
        tracer: tracer
      )
    end

    private

    def memory_store
      @memory_store ||= PersistentMemoryStore.new
    end

    def memory_retriever
      MemoryRetriever.new(
        store: memory_store,
        event_logger: @event_logger
      )
    end

    def tool_authorizer
      ToolAuthorizer.new(
        tool_catalog: tool_catalog,
        allowed_tools: ALLOWED_TOOLS,
        max_calls_per_tool: MAX_CALLS_PER_TOOL
      )
    end

    def planning_tool_catalog
      tool_catalog.only(ALLOWED_TOOLS)
    end

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

    def planner(tracer: Observability::NullTracer.new, client: llm_client)
      LlmPlanner.new(
        llm_client: client,
        registry: registry,
        tool_catalog: planning_tool_catalog,
        tool_validator: tool_validator,
        context_window: context_window,
        tracer: tracer
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

    def metered_llm_client(tracer:)
      MeteredLlmClient.new(
        client: llm_client,
        tracer: tracer,
        pricing_table: pricing_table,
        budget: LlmBudget.new(
          max_total_tokens: MAX_LLM_TOKENS_PER_RUN,
          max_cost_usd: MAX_LLM_COST_USD_PER_RUN
        ),
        model: LLM_MODEL
      )
    end

    def pricing_table
      @pricing_table ||= LlmPricingTable.load(LLM_PRICING_PATH)
    end

    def llm_client
      @llm_client ||= OpenAiLlmClient.new(
        client: openai_client,
        model: LLM_MODEL,
        output_schema: plan_output_schema,
        max_output_tokens: 2_000
      )
    end

    def plan_output_schema
      PlanOutputSchema.new(
        tool_catalog: planning_tool_catalog
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


require "openai"

module JobSearch
  class Container
    # Ferramentas e limites de cada agente vêm do AgentProfile: uma
    # ferramenta fora de allowed_tools não aparece para o LLM nem pode ser
    # executada por aquele agente.

    LLM_MODEL = "gpt-5.6".freeze
    LLM_PRICING_PATH = Rails.root.join("config/llm_pricing.yml")

    # Orçamento de LLM por run. 3 tentativas x (8k input + 2k output) já
    # cabem em 30k; o limite existe para que um laço futuro (ex.: agentes
    # delegando entre si) não gaste sem teto.
    MAX_LLM_TOKENS_PER_RUN = 30_000
    MAX_LLM_COST_USD_PER_RUN = 0.50

    # Delegações independentes rodam em paralelo até este limite. Cada
    # agente em execução pode segurar uma conexão do banco (memória e
    # auditoria): mantenha abaixo do pool (config/database.yml, padrão 5)
    # e abaixo do rate limit do provedor de LLM.
    MAX_PARALLEL_DELEGATIONS = 3

    # llm_client: permite trocar o LLM (ex.: cliente roteirizado nos testes
    # de integração) mantendo todo o resto da montagem real.
    #
    # event_logger: destino dos logs estruturados (padrão: Rails.logger).
    #
    # checkpoint: chamado antes de cada span (harness, Aula 45).
    def initialize(llm_client: nil, event_logger: Observability::EventLogger.new, checkpoint: nil)
      @llm_client = llm_client
      @event_logger = event_logger
      @checkpoint = checkpoint
    end

    # Monta um agente para um papel (profile).
    #
    # Sem tracer, o agente ganha um Tracer próprio (o run é a raiz do
    # trace, e o RunMetrics resume o run). Com tracer (ex.: dentro de um
    # pipeline multiagente), o run vira um ramo do trace de quem chamou.
    # O LLM é medido por um MeteredLlmClient com orçamento próprio do run.
    def agent(
      objective:,
      profile: AgentProfiles::GENERALIST,
      inputs: [],
      tracer: nil,
      parent_run_id: nil
    )
      tracer ||= new_tracer

      Agent.new(
        objective: objective,
        name: profile.name,
        inputs: inputs,
        parent_run_id: parent_run_id,
        planner: planner(
          tracer: tracer,
          client: metered_llm_client(tracer: tracer, profile: profile),
          profile: profile
        ),
        plan_executor: plan_executor(tracer: tracer, audit_trail: audit_trail, profile: profile),
        audit_trail: audit_trail,
        planning_retry_policy: planning_retry_policy,
        tracer: tracer,
        memory_store: memory_store,
        memory_retriever: memory_retriever
      )
    end

    # Pipeline multiagente: pesquisador -> analista, num único trace.
    def pipeline(stages: [ AgentProfiles::RESEARCHER, AgentProfiles::ANALYST ])
      MultiAgentPipeline.new(
        stages: stages,
        agent_factory: self,
        tracer: new_tracer,
        audit_trail: audit_trail
      )
    end

    # Supervisor: um LLM decide a quem delegar (Aula 42).
    def supervisor(team: AgentProfiles::TEAM)
      tracer = new_tracer

      Supervisor.new(
        delegation_planner: DelegationPlanner.new(
          llm_client: metered_llm_client(tracer: tracer, profile: nil, team: team),
          team: team,
          tracer: tracer
        ),
        executor: DelegationExecutor.new(
          agent_factory: self, profiles: team, tracer: tracer, audit_trail: audit_trail,
          max_parallel: MAX_PARALLEL_DELEGATIONS
        ),
        planning_retry_policy: planning_retry_policy,
        tracer: tracer,
        audit_trail: audit_trail
      )
    end

    # Cliente do LLM juiz dos evals (Aula 44): schema próprio (nota 1-5).
    def eval_judge_llm_client
      return @llm_client if @llm_client

      @eval_judge_llm_client ||= OpenAiLlmClient.new(
        client: openai_client,
        model: LLM_MODEL,
        output_schema: Evals::LlmJudge::SCHEMA,
        schema_name: "job_search_eval_judge",
        max_output_tokens: 300
      )
    end

    # Cada PlanExecutor tem o próprio budget, compartilhado apenas com o
    # seu Executor: execuções diferentes não somam tempo nem chamadas.
    def plan_executor(
      tracer: Observability::NullTracer.new,
      audit_trail: NullAuditTrail.new,
      profile: AgentProfiles::GENERALIST
    )
      budget = execution_budget

      PlanExecutor.new(
        executor: executor(execution_budget: budget),
        execution_budget: budget,
        tool_catalog: tool_catalog,
        tool_authorizer: tool_authorizer(audit_trail: audit_trail, profile: profile),
        tracer: tracer
      )
    end

    # Trilha de auditoria persistente (uma instância por Container; cada
    # run tem a própria cadeia, separada pelo run_id).
    def audit_trail
      @audit_trail ||= AuditTrail.new
    end

    private

    def new_tracer
      Observability::Tracer.new(
        event_logger: @event_logger,
        listeners: [ Observability::RunMetrics.new(event_logger: @event_logger) ],
        checkpoint: @checkpoint
      )
    end

    def memory_store
      @memory_store ||= PersistentMemoryStore.new
    end

    def memory_retriever
      MemoryRetriever.new(
        store: memory_store,
        event_logger: @event_logger
      )
    end

    def tool_authorizer(audit_trail:, profile:)
      ToolAuthorizer.new(
        tool_catalog: tool_catalog,
        allowed_tools: profile.allowed_tools,
        max_calls_per_tool: profile.max_calls_per_tool,
        audit_trail: audit_trail
      )
    end

    def planning_tool_catalog(profile = AgentProfiles::GENERALIST)
      tool_catalog.only(profile.allowed_tools)
    end

    def execution_budget
      ExecutionBudget.new(
        max_steps: 10,
        max_tool_calls: 20,
        max_execution_seconds: 30
      )
    end

    def timeout_policy
      # 15 s: a primeira busca de vagas baixa ~20 feeds (em paralelo, cada
      # um com timeouts de 3 s + 5 s; medido: ~7 s); depois vem do cache.
      @timeout_policy ||= TimeoutPolicy.new(
        timeout_seconds: 15
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

    def planner(
      tracer: Observability::NullTracer.new,
      profile: AgentProfiles::GENERALIST,
      client: llm_client(profile)
    )
      LlmPlanner.new(
        llm_client: client,
        registry: registry,
        tool_catalog: planning_tool_catalog(profile),
        tool_validator: tool_validator,
        context_window: context_window,
        tracer: tracer,
        role: profile.role
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

    # profile: nil + team -> cliente do supervisor (schema de delegação).
    def metered_llm_client(tracer:, profile:, team: nil)
      MeteredLlmClient.new(
        client: profile ? llm_client(profile) : supervisor_llm_client(team),
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

    # O schema de saída lista as ferramentas do papel, então cada papel
    # tem o seu cliente. Um llm_client injetado (testes) serve a todos.
    def llm_client(profile = AgentProfiles::GENERALIST)
      return @llm_client if @llm_client

      @llm_clients ||= {}
      @llm_clients[profile.name] ||= OpenAiLlmClient.new(
        client: openai_client,
        model: LLM_MODEL,
        output_schema: plan_output_schema(profile),
        max_output_tokens: 2_000
      )
    end

    def supervisor_llm_client(team)
      return @llm_client if @llm_client

      @llm_clients ||= {}
      @llm_clients["supervisor:#{team.map(&:name).join(',')}"] ||= OpenAiLlmClient.new(
        client: openai_client,
        model: LLM_MODEL,
        output_schema: DelegationOutputSchema.new(team: team).to_h,
        schema_name: "job_search_delegation",
        max_output_tokens: 1_000
      )
    end

    def plan_output_schema(profile = AgentProfiles::GENERALIST)
      PlanOutputSchema.new(
        tool_catalog: planning_tool_catalog(profile)
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

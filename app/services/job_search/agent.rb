require "digest"

module JobSearch
  class Agent
    attr_reader :objective, :name, :inputs, :parent_run_id

    # memory_store / memory_retriever são opcionais: sem eles o agente
    # funciona só com a memória de curto prazo. A memória persistente é
    # auxiliar e nunca derruba uma execução: falhas ao ler ou gravar são
    # registradas no log e o run continua.
    # name: papel do agente (separa a memória persistente por papel).
    # inputs: AgentInput recebidos de outro agente.
    # parent_run_id: run do coordenador que delegou este trabalho.
    def initialize(
      objective:,
      planner:,
      plan_executor:,
      planning_retry_policy:,
      memory_store: nil,
      memory_retriever: nil,
      event_logger: Observability::EventLogger.new,
      tracer: nil,
      audit_trail: NullAuditTrail.new,
      name: PersistentMemoryStore::DEFAULT_AGENT_NAME,
      inputs: [],
      parent_run_id: nil
    )
      @audit_trail = audit_trail
      @name = name.to_s
      @inputs = inputs
      @parent_run_id = parent_run_id
      @objective = objective
      @planner = planner
      @plan_executor = plan_executor
      @planning_retry_policy = planning_retry_policy
      @memory_store = memory_store
      @memory_retriever = memory_retriever
      @tracer = tracer || Observability::Tracer.new(event_logger: event_logger)
    end

    # Cada run é um trace (trace_id = run_id) com o span raiz agent.run.
    # run_id: opcional, para o run usar um id definido por fora (harness).
    def run(run_id: nil)
      state = AgentState.new(
        objective: objective,
        inputs: inputs,
        **{ run_id: run_id }.compact
      )

      @tracer.span(
        "agent.run",
        trace_id: state.run_id,
        run_id: state.run_id,
        agent: name,
        objective_chars: objective.to_s.length
      ) do |span|
        run_traced(state, span)
      end
    end

    private

    def run_traced(state, span)
      audit_run_started(state)

      lessons = retrieve_lessons(state)
      span.set(:lessons, lessons.size)

      plan = @planning_retry_policy.call(
        objective: objective,
        memory: state.memory,
        lessons: lessons,
        inputs: inputs
      ) do |context|
        plan_attempt(context)
      end

      @plan_executor.execute(
        plan: plan,
        state: state
      )

      state
    rescue StandardError => failure
      state.failed!
      raise
    ensure
      persist_memory(state)
      audit_run_finished(state, failure)
      span.set(:run_status, state.status.to_s)
    end

    # Fail closed: sem registro de início, o run não começa.
    # O objetivo não vai para a auditoria, só o digest: o texto fica na
    # memória do run (agent_memory_entries), com o mesmo run_id.
    def audit_run_started(state)
      @audit_trail.record(
        run_id: state.run_id,
        event: "run.started",
        outcome: "info",
        details: {
          agent: name,
          parent_run_id: parent_run_id,
          inputs: (inputs.map { |input| input.name.to_s } if inputs.any?),
          objective_sha256: Digest::SHA256.hexdigest(objective.to_s),
          objective_chars: objective.to_s.length
        }.compact
      )
    end

    # O fim do run é informativo: as decisões que importam (autorizações)
    # já foram gravadas antes de agir. Uma falha aqui só vai para o log,
    # para não esconder o erro original do run.
    def audit_run_finished(state, failure)
      details = { status: state.status.to_s }

      if failure
        details[:error_class] = failure.class.name
        details[:signals] = failure.signals.map(&:to_s) if failure.respond_to?(:signals)
      end

      @audit_trail.record(
        run_id: state.run_id,
        event: "run.finished",
        outcome: failure ? "failed" : "completed",
        details: details
      )
    rescue StandardError => error
      log_memory_failure("agent_audit.record_failed", state, error)
    end

    # O motivo da rejeição repete texto do LLM: vai higienizado e curto.
    def plan_attempt(context)
      @tracer.span(
        "planning.attempt",
        attempt: context.attempt,
        history: context.history.size
      ) do |span|
        @planner.plan(context: context)
      rescue PlanningError => error
        span.set(:retryable, error.retryable?)
        span.set(:rejection_reason, rejection_reason(error)) if error.retryable?
        raise
      end
    end

    def rejection_reason(error)
      UntrustedText.sanitize(
        error.cause&.message || error.message,
        max_length: 200,
        single_line: true
      )
    end

    def retrieve_lessons(state)
      return [] unless @memory_retriever

      @memory_retriever.lessons_for(
        objective: objective,
        exclude_run_id: state.run_id,
        agent_name: name
      )
    rescue StandardError => error
      log_memory_failure("agent_memory.retrieve_failed", state, error)
      []
    end

    def persist_memory(state)
      return unless @memory_store

      state.memory.record(:run_finished, "status: #{state.status}")

      @memory_store.save(
        run_id: state.run_id,
        objective: objective,
        memory: state.memory,
        agent_name: name
      )
    rescue StandardError => error
      log_memory_failure("agent_memory.persist_failed", state, error)
    end

    def log_memory_failure(event, state, error)
      @tracer.log(
        :warn,
        event: event,
        run_id: state.run_id,
        error_class: error.class.name,
        error_message: error.message
      )
    end
  end
end

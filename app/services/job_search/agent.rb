module JobSearch
  class Agent
    attr_reader :objective

    # memory_store / memory_retriever são opcionais: sem eles o agente
    # funciona só com a memória de curto prazo. A memória persistente é
    # auxiliar e nunca derruba uma execução: falhas ao ler ou gravar são
    # registradas no log e o run continua.
    def initialize(
      objective:,
      planner:,
      plan_executor:,
      planning_retry_policy:,
      memory_store: nil,
      memory_retriever: nil,
      event_logger: Observability::EventLogger.new,
      tracer: nil
    )
      @objective = objective
      @planner = planner
      @plan_executor = plan_executor
      @planning_retry_policy = planning_retry_policy
      @memory_store = memory_store
      @memory_retriever = memory_retriever
      @tracer = tracer || Observability::Tracer.new(event_logger: event_logger)
    end

    # Cada run é um trace (trace_id = run_id) com o span raiz agent.run.
    def run
      state = AgentState.new(
        objective: objective
      )

      @tracer.span(
        "agent.run",
        trace_id: state.run_id,
        run_id: state.run_id,
        objective_chars: objective.to_s.length
      ) do |span|
        run_traced(state, span)
      end
    end

    private

    def run_traced(state, span)
      lessons = retrieve_lessons(state)
      span.set(:lessons, lessons.size)

      plan = @planning_retry_policy.call(
        objective: objective,
        memory: state.memory,
        lessons: lessons
      ) do |context|
        plan_attempt(context)
      end

      @plan_executor.execute(
        plan: plan,
        state: state
      )

      state
    rescue StandardError
      state.failed!
      raise
    ensure
      persist_memory(state)
      span.set(:run_status, state.status.to_s)
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
        exclude_run_id: state.run_id
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
        memory: state.memory
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

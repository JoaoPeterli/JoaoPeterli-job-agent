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
      event_logger: Observability::EventLogger.new
    )
      @objective = objective
      @planner = planner
      @plan_executor = plan_executor
      @planning_retry_policy = planning_retry_policy
      @memory_store = memory_store
      @memory_retriever = memory_retriever
      @event_logger = event_logger
    end

    def run
      state = AgentState.new(
        objective: objective
      )

      plan = @planning_retry_policy.call(
        objective: objective,
        memory: state.memory,
        lessons: retrieve_lessons(state)
      ) do |context|
        @planner.plan(context: context)
      end

      @plan_executor.execute(
        plan: plan,
        state: state
      )

      state
    rescue StandardError
      state&.failed!
      raise
    ensure
      persist_memory(state) if state
    end

    private

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
      @event_logger.warn(
        event: event,
        run_id: state.run_id,
        error_class: error.class.name,
        error_message: error.message
      )
    end
  end
end

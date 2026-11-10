module JobSearch
  class PlanExecutor
    # tool_authorizer: por padrão libera as ferramentas do catálogo, mas
    # nega toda ação com efeito colateral sem aprovação (padrão seguro).
    def initialize(
      executor:,
      execution_budget:,
      tool_catalog:,
      tool_authorizer: ToolAuthorizer.new(tool_catalog: tool_catalog),
      tracer: Observability::NullTracer.new
    )
      @executor = executor
      @execution_budget = execution_budget
      @tool_catalog = tool_catalog
      @tool_authorizer = tool_authorizer
      @tracer = tracer
    end

    def execute(plan:, state:)
      @tracer.span("plan.execute", steps: plan.steps.length) do
        execute_plan(plan, state)
      end
    end

    private

    def execute_plan(plan, state)
      # Tempo e chamadas contam a partir do início da execução do plano,
      # não da construção do budget (o planejamento via LLM vem antes).
      @execution_budget.start!
      @execution_budget.validate!(plan: plan)
      @tool_authorizer.start!
      @tool_authorizer.authorize_plan!(plan, run_id: state.run_id)

      state.memory.record(
        :plan_started,
        "#{plan.steps.length} steps: #{plan.steps.map(&:name).join(', ')}"
      )

      completed_steps = []

      while completed_steps.length < plan.steps.length
        ready_steps = plan.ready_steps(
          completed_steps: completed_steps
        )

        if ready_steps.empty?
          raise "No executable steps available"
        end

        ready_steps.each do |step|
          execute_step(step, state: state)
          completed_steps << step.name
        end
      end

      state.complete!
    rescue StandardError
      state.failed!
      raise
    end

    def execute_step(step, state:)
      @tracer.span("step", step: step.name.to_s, tool: step.action.tool.to_s) do |span|
        run_step(step, state: state)
      ensure
        span.set(:attempts, state.attempts_for(step.name).to_i)
      end
    end

    def run_step(step, state:)
      state.start_step!(step.name)

      action = step.action
      state.add_action(action)

      resolved_arguments = resolve_arguments(
        action.arguments,
        state: state
      )

      executable_action = AgentAction.new(
        tool: action.tool,
        arguments: resolved_arguments
      )

      @tool_authorizer.authorize!(executable_action, run_id: state.run_id)

      result = @executor.execute(
        executable_action,
        on_attempt: ->(attempt) {
          state.record_attempt(step.name, attempt)
        },
        idempotency_key: idempotency_key(state, step, executable_action)
      )

      state.add_observation(step.name, result)
      state.complete_step!(step.name)
      state.memory.record(:step_completed, "#{step.name} (#{action.tool})")

    rescue StandardError => error
      state.fail_step!(
        step.name,
        error: error
      )
      state.memory.record(
        :step_failed,
        "#{step.name} (#{step.action.tool}): #{error.class}: #{error.message}"
      )
      raise
    end

    # Ferramentas com efeito colateral usam uma chave semântica (ferramenta
    # + argumentos resolvidos), estável entre execuções do agente: se o
    # processo cair e o agente rodar de novo, a mesma candidatura não é
    # enviada duas vezes. O nome do passo não entra na chave porque vem do
    # LLM e pode mudar entre planos.
    #
    # Ferramentas somente leitura usam uma chave por execução, para que
    # uma nova execução busque dados atualizados em vez de reutilizar o
    # resultado gravado.
    def idempotency_key(state, step, action)
      definition = @tool_catalog.fetch(action.tool)

      if definition.side_effects
        fingerprint = OperationFingerprint.call(
          tool: action.tool,
          arguments: action.arguments
        )

        "#{action.tool}:#{fingerprint}"
      else
        "#{state.run_id}:#{step.name}"
      end
    end

    def resolve_arguments(arguments, state:)
      resolve_value(arguments, state: state)
    end

    def resolve_value(value, state:)
      case value
      when ObservationReference
        state.observation_for(value.step_name)

      when Hash
        value.transform_values do |nested_value|
          resolve_value(nested_value, state: state)
        end

      when Array
        value.map do |nested_value|
          resolve_value(nested_value, state: state)
        end

      else
        value
      end
    end
  end
end

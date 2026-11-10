module JobSearch
  class Executor
    def initialize(
      registry:,
      retry_policy:,
      tool_catalog:,
      tool_validator:,
      execution_budget:,
      timeout_policy:,
      idempotency_policy: nil
    )
      @registry = registry
      @retry_policy = retry_policy
      @tool_catalog = tool_catalog
      @tool_validator = tool_validator
      @execution_budget = execution_budget
      @timeout_policy = timeout_policy
      @idempotency_policy = idempotency_policy
    end

    def execute(action, on_attempt: nil, idempotency_key: nil)
      definition = @tool_catalog.fetch(action.tool)

      @tool_validator.validate!(
        arguments: action.arguments,
        schema: definition.argument_schema
      )

      tool_class = @registry.fetch(action.tool)

      # O IdempotencyPolicy entrega o Lease adquirido ao bloco.
      operation = lambda do |lease|
        execute_tool(
          tool_class,
          action,
          on_attempt: on_attempt,
          max_attempts: definition.side_effects ? 1 : nil,
          lease: lease
        )
      end

      if idempotency_key
        unless @idempotency_policy
          raise ArgumentError, "IdempotencyPolicy is not configured"
        end

        @idempotency_policy.call(
          key: idempotency_key,
          recover_expired: !definition.side_effects,
          operation_type: definition.operation_type,
          side_effects: definition.side_effects,
          &operation
        )
      else
        operation.call(nil)
      end
    end

    private

    def execute_tool(tool_class, action, on_attempt:, max_attempts:, lease:)
      tool = tool_class.new
      arguments = tool_arguments(tool, action, lease)

      retry_options = { on_attempt: on_attempt }
      retry_options[:max_attempts] = max_attempts if max_attempts

      @retry_policy.call(**retry_options) do
        @execution_budget.validate_execution_time!
        @execution_budget.consume_tool_call!

        @timeout_policy.call do
          tool.call(**arguments)
        end
      end
    end

    # O lease (chave de idempotência + fencing token) só é entregue a
    # ferramentas que declaram o argumento `lease:`. Ele nunca vem do
    # plano: o ToolValidator rejeita argumentos fora do schema.
    def tool_arguments(tool, action, lease)
      return action.arguments unless lease && accepts_lease?(tool)

      action.arguments.merge(lease: lease)
    end

    def accepts_lease?(tool)
      tool.method(:call).parameters.any? do |type, name|
        name == :lease && %i[key keyreq].include?(type)
      end
    end
  end
end

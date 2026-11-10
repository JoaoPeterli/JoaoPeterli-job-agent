module JobSearch
  # Autorização de ferramentas, aplicada fora do LLM: nenhuma instrução no
  # prompt (nem uma injeção bem-sucedida) muda o que pode ser executado.
  #
  # 1. Allowlist: só ferramentas liberadas para este agente.
  # 2. Limite por ferramenta em cada run (ex.: no máximo N buscas).
  # 3. Ferramentas com efeito colateral exigem aprovação da ação exata.
  #
  # Tem estado (contagem de chamadas): start! zera a contagem no início
  # de cada plano, como o ExecutionBudget.
  class ToolAuthorizer
    def initialize(
      tool_catalog:,
      allowed_tools: nil,
      max_calls_per_tool: {},
      approval_gate: DenyAllApprovalGate.new
    )
      @tool_catalog = tool_catalog
      @allowed_tools = allowed_tools&.map(&:to_sym)
      @max_calls_per_tool = max_calls_per_tool.transform_keys(&:to_sym)
      @approval_gate = approval_gate
      @calls = Hash.new(0)
    end

    def start!
      @calls = Hash.new(0)

      self
    end

    def permitted?(tool)
      @allowed_tools.nil? || @allowed_tools.include?(tool.to_sym)
    end

    # Checagem antecipada do plano inteiro (antes de executar qualquer
    # passo): allowlist e limites. Evita executar metade de um plano que
    # seria barrado no meio.
    def authorize_plan!(plan)
      counts = Hash.new(0)

      plan.steps.each do |step|
        tool = step.action.tool.to_sym
        check_permitted!(tool)
        counts[tool] += 1
      end

      counts.each do |tool, count|
        limit = @max_calls_per_tool[tool]
        next if limit.nil? || count <= limit

        raise ToolCallLimitExceeded,
              "Plan uses #{tool} #{count} times (limit: #{limit})"
      end

      true
    end

    # Checagem de cada ação com os argumentos já resolvidos, logo antes
    # de executar. A aprovação só pode ser verificada aqui, porque os
    # argumentos finais dependem das observações de passos anteriores.
    def authorize!(action, run_id:)
      tool = action.tool.to_sym

      check_permitted!(tool)
      check_limit!(tool)
      check_approval!(action, run_id: run_id)

      @calls[tool] += 1

      true
    end

    private

    def check_permitted!(tool)
      return if permitted?(tool)

      raise ToolNotAuthorizedError, "Tool not authorized: #{tool}"
    end

    def check_limit!(tool)
      limit = @max_calls_per_tool[tool]
      return if limit.nil? || @calls[tool] < limit

      raise ToolCallLimitExceeded,
            "Tool #{tool} exceeded #{limit} calls in this run"
    end

    def check_approval!(action, run_id:)
      definition = @tool_catalog.fetch(action.tool)
      return unless definition.side_effects

      fingerprint = OperationFingerprint.call(
        tool: action.tool,
        arguments: action.arguments
      )

      return if @approval_gate.approved?(tool: action.tool, fingerprint: fingerprint, run_id: run_id)

      raise ApprovalRequiredError.new(
        "Approval required for #{action.tool}",
        tool: action.tool,
        fingerprint: fingerprint
      )
    end
  end
end

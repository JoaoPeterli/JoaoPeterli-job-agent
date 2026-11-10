module JobSearch
  # Valida o plano de delegação devolvido pelo LLM supervisor e o
  # transforma em Delegations.
  #
  # O LLM decide O QUE delegar, mas o código decide o que é PERMITIDO:
  # - só agentes do time (allowlist), nunca o próprio coordenador;
  # - no máximo max_delegations tarefas (teto de custo e de "fan-out");
  # - inputs só de delegações anteriores (sem ciclos, sem referência ao
  #   futuro) e compatíveis com o contrato do agente (required_inputs);
  # - o texto da tarefa vira objetivo de outro LLM, então passa pelo
  #   mesmo detector de injeção do objetivo do usuário.
  #
  # Erros de estrutura são PlanValidationError (o supervisor pode
  # corrigir na próxima tentativa); injeção é UntrustedInputError (para).
  class DelegationPlanValidator
    ID_FORMAT = /\A[a-z][a-z0-9_]{0,39}\z/
    MAX_TASK_LENGTH = 300

    attr_reader :max_delegations

    def initialize(team:, max_delegations: 4, injection_detector: InjectionDetector.new)
      @team = team.to_h { |profile| [ profile.name, profile ] }
      @max_delegations = max_delegations
      @injection_detector = injection_detector
    end

    def validate!(data)
      items = delegation_items(data)
      delegations = []

      items.each do |item|
        delegation = build(item, delegations)
        check_inputs!(delegation, delegations)
        delegations << delegation
      end

      check_injection!(delegations)
      delegations
    end

    private

    def delegation_items(data)
      items = data.is_a?(Hash) ? data[:delegations] : nil
      invalid!("Delegation plan must contain a delegations array") unless items.is_a?(Array)

      unless items.size.between?(1, @max_delegations)
        invalid!("Delegation plan must have between 1 and #{@max_delegations} delegations")
      end

      items
    end

    def build(item, previous)
      invalid!("Each delegation must be an object") unless item.is_a?(Hash)

      id = item[:id]
      invalid!("Invalid delegation id: #{id.to_s[0, 40]}") unless id.is_a?(String) && id.match?(ID_FORMAT)
      invalid!("Duplicated delegation: #{id}") if previous.any? { |delegation| delegation.id == id }

      agent = item[:agent].to_s
      invalid!("Unknown agent: #{agent[0, 40]}") unless @team.key?(agent)

      task = item[:task]
      unless task.is_a?(String) && !task.strip.empty? && task.length <= MAX_TASK_LENGTH
        invalid!("Delegation #{id}: task must have 1 to #{MAX_TASK_LENGTH} characters")
      end

      inputs = item.fetch(:inputs, [])
      invalid!("Delegation #{id}: inputs must be a list of delegation ids") unless inputs.is_a?(Array) && inputs.all?(String)

      Delegation.new(id: id, agent: agent, task: task.strip, inputs: inputs.uniq)
    end

    def check_inputs!(delegation, previous)
      by_id = previous.to_h { |item| [ item.id, item ] }
      profile = @team.fetch(delegation.agent)

      delegation.inputs.each do |source_id|
        next if by_id.key?(source_id)

        invalid!("Delegation #{delegation.id} uses unknown or later delegation: #{source_id[0, 40]}")
      end

      produced = delegation.inputs.map { |source_id| @team.fetch(by_id.fetch(source_id).agent).output_name }

      (produced - profile.required_inputs).uniq.each do |name|
        invalid!("Delegation #{delegation.id} (#{profile.name}) does not accept input #{name}")
      end

      (profile.required_inputs - produced).each do |name|
        invalid!("Delegation #{delegation.id} (#{profile.name}) requires input #{name}")
      end
    end

    def check_injection!(delegations)
      signals = delegations.flat_map { |delegation| @injection_detector.detect(delegation.task) }.uniq
      return if signals.empty?

      raise UntrustedInputError.new("Delegated task rejected: possible prompt injection", signals: signals)
    end

    def invalid!(message)
      raise PlanValidationError, message
    end
  end
end

require "digest"
require "json"

module JobSearch
  # Executa uma lista de delegações, em ordem, ligando o output de uma
  # ao input das seguintes. É o motor comum do pipeline fixo (Aula 41) e
  # do supervisor (Aula 42): os dois só diferem em QUEM monta a lista.
  #
  # - Inputs com o mesmo nome (ex.: duas buscas entregando "jobs") são
  #   somados: listas são concatenadas.
  # - Uma delegação cujos inputs vieram todos vazios é pulada (status
  #   :skipped na mensagem, time :stopped_early): nada para analisar =
  #   nenhuma chamada de LLM desperdiçada. Delegações que dependem de uma
  #   pulada também são puladas.
  # - Cada repasse de dado é auditado na cadeia do coordenador (origem,
  #   destino, tamanho e SHA-256 do dado, nunca o dado).
  class DelegationExecutor
    COORDINATOR = "coordinator".freeze

    def initialize(agent_factory:, profiles:, tracer:, audit_trail:)
      @agent_factory = agent_factory
      @profiles = profiles.to_h { |profile| [ profile.name, profile ] }
      @tracer = tracer
      @audit_trail = audit_trail
    end

    def run(run_id:, delegations:)
      context = { run_id: run_id, messages: [], outputs: {}, agent_run_ids: {}, skipped: [] }

      delegations.each do |delegation|
        inputs = inputs_for(delegation, context)

        if skip?(delegation, inputs, context)
          context[:skipped] << delegation.id
          context[:messages] << message(:result, from: delegation.agent, run_id: run_id,
                                                 delegation: delegation.id, status: "skipped")
          next
        end

        audit_handoffs(run_id, delegation, context)
        run_delegation(delegation, inputs, context)
      end

      TeamResult.new(
        run_id: run_id,
        status: context[:skipped].empty? ? :completed : :stopped_early,
        output: context[:outputs].values.last,
        outputs: context[:outputs].freeze,
        messages: context[:messages].freeze,
        agent_run_ids: context[:agent_run_ids].freeze
      )
    end

    private

    def run_delegation(delegation, inputs, context)
      profile = @profiles.fetch(delegation.agent)
      context[:messages] << message(:task, to: delegation.agent, run_id: context[:run_id],
                                           delegation: delegation.id, inputs: inputs.map(&:summary))

      state = @tracer.span("delegation", delegation: delegation.id, agent: profile.name) do
        @agent_factory.agent(
          objective: delegation.task,
          profile: profile,
          inputs: inputs,
          tracer: @tracer,
          parent_run_id: context[:run_id]
        ).run
      end

      output = profile.output_input(state)
      context[:agent_run_ids][delegation.id] = state.run_id
      context[:outputs][delegation.id] = output
      context[:messages] << message(:result, from: delegation.agent, run_id: context[:run_id],
                                             delegation: delegation.id, agent_run_id: state.run_id,
                                             status: state.status.to_s, output: output.summary)
    rescue StandardError => error
      context[:messages] << message(:failure, from: delegation.agent, run_id: context[:run_id],
                                              delegation: delegation.id, error_class: error.class.name)

      raise PipelineStageError.new(
        "Delegation #{delegation.id} (#{delegation.agent}) failed: #{error.class.name}",
        stage: delegation.id, pipeline_run_id: context[:run_id], messages: context[:messages]
      )
    end

    # Junta os outputs das delegações de origem; mesmo nome -> soma.
    def inputs_for(delegation, context)
      delegation.inputs
        .filter_map { |id| context[:outputs][id] }
        .group_by(&:name)
        .map do |name, group|
          values = group.map(&:value)
          value = values.all?(Array) ? values.flatten(1) : values.last

          AgentInput.new(name: name, description: group.first.description, value: value)
        end
    end

    def skip?(delegation, inputs, context)
      return false if delegation.inputs.empty?
      return true if delegation.inputs.any? { |id| context[:skipped].include?(id) }

      inputs.all? { |input| blank?(input.value) }
    end

    def audit_handoffs(run_id, delegation, context)
      delegation.inputs.each do |source_id|
        input = context[:outputs].fetch(source_id)

        @audit_trail.record(
          run_id: run_id, event: "agent.handoff", outcome: "info",
          details: {
            from: source_id, to: delegation.id, input: input.name.to_s,
            items: input.value.respond_to?(:size) ? input.value.size : nil,
            sha256: Digest::SHA256.hexdigest(JSON.generate(input.value))
          }.compact
        )
      end
    end

    def message(kind, run_id:, from: COORDINATOR, to: COORDINATOR, **payload)
      AgentMessage.new(kind: kind, from: from, to: to, pipeline_run_id: run_id, payload: payload).tap do |msg|
        @tracer.log(:info, event: "agent.message", kind: kind.to_s, from: from, to: to, message_id: msg.id)
      end
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end

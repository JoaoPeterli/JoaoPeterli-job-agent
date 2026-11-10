require "digest"
require "json"

module JobSearch
  # Executa uma lista de delegações, ligando o output de uma ao input das
  # seguintes. É o motor comum do pipeline fixo (Aula 41) e do supervisor
  # (Aula 42): os dois só diferem em QUEM monta a lista.
  #
  # Execução em waves (Aula 43): a wave de uma delegação é 0 se ela não
  # tem inputs, senão 1 + a maior wave das suas fontes. Delegações da
  # mesma wave são independentes e rodam em paralelo (até max_parallel);
  # a próxima wave só começa quando a anterior termina.
  #
  # - Agentes são montados na thread do coordenador (o Container memoiza
  #   com ||=, que não é thread-safe); só o #run vai para as threads. Por
  #   dentro, cada agente continua single-threaded e isolado.
  # - Fail-fast por wave: se alguma delegação falha, as que já estão
  #   rodando terminam (thread não é interrompida no meio de uma chamada
  #   de ferramenta), mas nenhuma wave nova começa. O erro reportado é o
  #   da primeira delegação que falhou na ordem do plano (determinístico).
  # - Mensagens, outputs e auditoria saem sempre na ordem do plano, não
  #   na ordem em que as threads terminaram.
  # - Inputs com o mesmo nome são somados (listas concatenadas).
  # - Delegação sem dado para trabalhar (inputs vazios ou fonte pulada) é
  #   pulada; o time termina :stopped_early.
  class DelegationExecutor
    COORDINATOR = "coordinator".freeze

    def initialize(agent_factory:, profiles:, tracer:, audit_trail:, max_parallel: 1)
      @agent_factory = agent_factory
      @profiles = profiles.to_h { |profile| [ profile.name, profile ] }
      @tracer = tracer
      @audit_trail = audit_trail
      @runner = ParallelRunner.new(max_parallel: max_parallel)
      @max_parallel = max_parallel
    end

    def run(run_id:, delegations:)
      context = { run_id: run_id, messages: [], outputs: {}, agent_run_ids: {}, skipped: [] }

      waves(delegations).each_with_index do |wave, index|
        run_wave(wave, index, context)
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

    def waves(delegations)
      levels = {}

      delegations.each do |delegation|
        levels[delegation.id] = delegation.inputs.map { |id| levels.fetch(id) + 1 }.max || 0
      end

      delegations.group_by { |delegation| levels[delegation.id] }.sort.map(&:last)
    end

    def run_wave(wave, index, context)
      runnable = wave.reject { |delegation| skip!(delegation, context) }
      return if runnable.empty?

      @tracer.span("delegation.wave", wave: index, size: runnable.size,
                                      parallel: [ runnable.size, @max_parallel ].min) do |span|
        jobs = runnable.map { |delegation| prepare(delegation, context) }
        parent = span

        outcomes = @runner.map(jobs) do |job|
          @tracer.attach(parent) { execute(job) }
        end

        collect(jobs, outcomes, context)
      end
    end

    # Na thread do coordenador: auditoria do handoff, mensagem de tarefa
    # e montagem do agente.
    def prepare(delegation, context)
      profile = @profiles.fetch(delegation.agent)
      inputs = inputs_for(delegation, context)

      audit_handoffs(context[:run_id], delegation, context)
      context[:messages] << message(:task, to: delegation.agent, run_id: context[:run_id],
                                           delegation: delegation.id, inputs: inputs.map(&:summary))

      agent = @agent_factory.agent(
        objective: delegation.task,
        profile: profile,
        inputs: inputs,
        tracer: @tracer,
        parent_run_id: context[:run_id]
      )

      { delegation: delegation, profile: profile, agent: agent }
    end

    # Na thread worker: só o run do agente.
    def execute(job)
      @tracer.span("delegation", delegation: job[:delegation].id, agent: job[:profile].name) do
        job[:agent].run
      end
    end

    def collect(jobs, outcomes, context)
      failures = []

      jobs.zip(outcomes).each do |job, outcome|
        delegation = job[:delegation]

        if outcome.ok?
          record_result(job, outcome.value, context)
        else
          failures << [ delegation, outcome.error ]
          context[:messages] << message(:failure, from: delegation.agent, run_id: context[:run_id],
                                                  delegation: delegation.id, error_class: outcome.error.class.name)
        end
      end

      return if failures.empty?

      delegation, error = failures.first
      raise PipelineStageError.new(
        "Delegation #{delegation.id} (#{delegation.agent}) failed: #{error.class.name}",
        stage: delegation.id, pipeline_run_id: context[:run_id], messages: context[:messages]
      ), cause: error
    end

    def record_result(job, state, context)
      delegation = job[:delegation]
      output = job[:profile].output_input(state)

      context[:agent_run_ids][delegation.id] = state.run_id
      context[:outputs][delegation.id] = output
      context[:messages] << message(:result, from: delegation.agent, run_id: context[:run_id],
                                             delegation: delegation.id, agent_run_id: state.run_id,
                                             status: state.status.to_s, output: output.summary)
    end

    def skip!(delegation, context)
      return false unless skip?(delegation, inputs_for(delegation, context), context)

      context[:skipped] << delegation.id
      context[:messages] << message(:result, from: delegation.agent, run_id: context[:run_id],
                                             delegation: delegation.id, status: "skipped")
      true
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

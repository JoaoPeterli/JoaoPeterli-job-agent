require "digest"
require "json"
require "securerandom"

module JobSearch
  # Coordenação multiagente com topologia fixa (pipeline): cada estágio é
  # um agente especializado, e o output de um vira input do próximo.
  #
  # A ordem é decidida em código, não por um LLM: previsível, barata e
  # fácil de testar. (Delegação decidida por LLM é a Aula 42.)
  #
  # - Isolamento: cada agente tem run_id, memória, ferramentas, limites e
  #   orçamento de LLM próprios; nada é compartilhado além do input.
  # - Um trace: todos os agentes são ramos do span pipeline.run.
  # - Auditoria: o pipeline tem cadeia própria (run_id do pipeline) com
  #   início, cada handoff (de quem, para quem, tamanho e digest do dado)
  #   e fim; cada agente audita o próprio run com parent_run_id.
  # - Para cedo: se um estágio entrega um output vazio, os seguintes não
  #   rodam (nada para analisar = nenhuma chamada de LLM desperdiçada).
  class MultiAgentPipeline
    COORDINATOR = "coordinator".freeze

    Result = Data.define(:run_id, :status, :output, :messages, :agent_run_ids)

    def initialize(
      stages:,
      agent_factory:,
      tracer: Observability::NullTracer.new,
      audit_trail: NullAuditTrail.new,
      id_generator: -> { SecureRandom.uuid }
    )
      raise ArgumentError, "A pipeline needs at least one stage" if stages.empty?
      raise ArgumentError, "Every stage must declare an output" unless stages.all?(&:output_tool)

      @stages = stages
      @agent_factory = agent_factory
      @tracer = tracer
      @audit_trail = audit_trail
      @id_generator = id_generator
    end

    def run(objective:)
      run_id = @id_generator.call

      @tracer.span("pipeline.run", trace_id: run_id, run_id: run_id, stages: stage_names.join(",")) do |span|
        audit(run_id, "pipeline.started", "info",
              stages: stage_names, objective_sha256: Digest::SHA256.hexdigest(objective.to_s))

        result = run_stages(run_id, objective)
        span.set(:pipeline_status, result.status.to_s)
        audit(run_id, "pipeline.finished", "completed", status: result.status.to_s)
        result
      end
    end

    private

    def run_stages(run_id, objective)
      messages = []
      agent_run_ids = {}
      inputs = []
      output = nil

      @stages.each_with_index do |profile, index|
        state = run_stage(run_id, profile, objective, inputs, messages)
        agent_run_ids[profile.name] = state.run_id
        output = profile.output_input(state)

        messages << message(:result, from: profile.name, to: COORDINATOR, run_id: run_id,
                                     agent_run_id: state.run_id, status: state.status.to_s,
                                     output: output.summary)

        next_profile = @stages[index + 1]
        break unless next_profile

        if blank?(output.value)
          return Result.new(run_id, :stopped_early, output, messages.freeze, agent_run_ids.freeze)
        end

        audit_handoff(run_id, from: profile, to: next_profile, input: output)
        inputs = [ output ]
      end

      Result.new(run_id, :completed, output, messages.freeze, agent_run_ids.freeze)
    end

    def run_stage(run_id, profile, objective, inputs, messages)
      messages << message(:task, from: COORDINATOR, to: profile.name, run_id: run_id,
                                 inputs: inputs.map(&:summary))

      @tracer.span("pipeline.stage", agent: profile.name) do
        @agent_factory.agent(
          objective: objective,
          profile: profile,
          inputs: inputs,
          tracer: @tracer,
          parent_run_id: run_id
        ).run
      end
    rescue StandardError => error
      messages << message(:failure, from: profile.name, to: COORDINATOR, run_id: run_id,
                                    error_class: error.class.name)
      audit(run_id, "pipeline.finished", "failed", status: "failed", stage: profile.name,
                                                   error_class: error.class.name)

      raise PipelineStageError.new(
        "Pipeline stage #{profile.name} failed: #{error.class.name}",
        stage: profile.name, pipeline_run_id: run_id, messages: messages
      )
    end

    def message(kind, from:, to:, run_id:, **payload)
      AgentMessage.new(kind: kind, from: from, to: to, pipeline_run_id: run_id, payload: payload).tap do |msg|
        @tracer.log(:info, event: "agent.message", kind: kind.to_s, from: from, to: to, message_id: msg.id)
      end
    end

    # O digest prova qual dado exato passou de um agente para o outro sem
    # gravar o dado na auditoria.
    def audit_handoff(run_id, from:, to:, input:)
      audit(run_id, "agent.handoff", "info",
            from: from.name, to: to.name, input: input.name.to_s,
            items: input.value.respond_to?(:size) ? input.value.size : nil,
            sha256: Digest::SHA256.hexdigest(JSON.generate(input.value)))
    end

    def audit(run_id, event, outcome, **details)
      @audit_trail.record(run_id: run_id, event: event, outcome: outcome, details: details.compact)
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def stage_names
      @stages.map(&:name)
    end
  end
end

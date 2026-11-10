require "digest"
require "securerandom"

module JobSearch
  # Coordenação multiagente com topologia fixa (pipeline): cada estágio é
  # um agente especializado, e o output de um vira input do próximo.
  #
  # A ordem é decidida em código, não por um LLM: previsível, barata e
  # fácil de testar. O Supervisor (Aula 42) usa o mesmo DelegationExecutor,
  # mas deixa um LLM montar a lista de delegações.
  #
  # - Isolamento: cada agente tem run_id, memória, ferramentas, limites e
  #   orçamento de LLM próprios; nada é compartilhado além do input.
  # - Um trace: todos os agentes são ramos do span pipeline.run.
  # - Auditoria: o pipeline tem cadeia própria com início, cada handoff e
  #   fim; cada agente audita o próprio run com parent_run_id.
  class MultiAgentPipeline
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
      @tracer = tracer
      @audit_trail = audit_trail
      @id_generator = id_generator
      @executor = DelegationExecutor.new(
        agent_factory: agent_factory, profiles: stages, tracer: tracer, audit_trail: audit_trail
      )
    end

    def run(objective:)
      run_id = @id_generator.call

      @tracer.span("pipeline.run", trace_id: run_id, run_id: run_id, stages: stage_names.join(",")) do |span|
        audit(run_id, "pipeline.started", "info",
              stages: stage_names, objective_sha256: Digest::SHA256.hexdigest(objective.to_s))

        result = @executor.run(run_id: run_id, delegations: delegations(objective))
        span.set(:pipeline_status, result.status.to_s)
        audit(run_id, "pipeline.finished", "completed", status: result.status.to_s)
        result
      rescue PipelineStageError => error
        audit(run_id, "pipeline.finished", "failed",
              status: "failed", stage: error.stage, error_class: error.cause&.class&.name)
        raise
      end
    end

    private

    # Cada estágio recebe o objetivo original e o output do anterior.
    def delegations(objective)
      @stages.each_with_index.map do |profile, index|
        Delegation.new(
          id: profile.name,
          agent: profile.name,
          task: objective,
          inputs: index.zero? ? [] : [ @stages[index - 1].name ]
        )
      end
    end

    def audit(run_id, event, outcome, **details)
      @audit_trail.record(run_id: run_id, event: event, outcome: outcome, details: details.compact)
    end

    def stage_names
      @stages.map(&:name)
    end
  end
end

require "digest"
require "securerandom"

module JobSearch
  # Coordenação por delegação: um LLM supervisor decide quais
  # especialistas chamar, com que tarefa e em que ordem; o
  # DelegationExecutor executa.
  #
  # Garantias (todas fora do LLM):
  # - o supervisor não tem ferramentas, só escolhe entre especialistas
  #   aprovados (TEAM), e cada especialista mantém as próprias permissões
  #   seja qual for o texto da tarefa;
  # - profundidade 1: especialistas são Agents comuns e não delegam, então
  #   não existe recursão de delegação nem laço entre agentes;
  # - o plano é validado como contrato (agentes, inputs, limite de tarefas)
  #   e reparado com o mesmo PlanningRetryPolicy dos planos de ferramentas;
  # - tudo num trace (supervisor.run) e numa cadeia de auditoria própria.
  class Supervisor
    def initialize(
      delegation_planner:,
      executor:,
      planning_retry_policy: PlanningRetryPolicy.new(max_attempts: 3),
      tracer: Observability::NullTracer.new,
      audit_trail: NullAuditTrail.new,
      id_generator: -> { SecureRandom.uuid }
    )
      @delegation_planner = delegation_planner
      @executor = executor
      @planning_retry_policy = planning_retry_policy
      @tracer = tracer
      @audit_trail = audit_trail
      @id_generator = id_generator
    end

    def run(objective:)
      run_id = @id_generator.call

      @tracer.span("supervisor.run", trace_id: run_id, run_id: run_id) do |span|
        audit(run_id, "supervisor.started", "info", objective_sha256: Digest::SHA256.hexdigest(objective.to_s))

        delegations = plan(run_id, objective, span)
        result = @executor.run(run_id: run_id, delegations: delegations)

        span.set(:team_status, result.status.to_s)
        audit(run_id, "supervisor.finished", "completed", status: result.status.to_s)
        result
      rescue StandardError => error
        audit_failure(run_id, error)
        raise
      end
    end

    private

    def plan(run_id, objective, span)
      delegations = @planning_retry_policy.call(objective: objective) do |context|
        @tracer.span("delegation.attempt", attempt: context.attempt) do |attempt_span|
          @delegation_planner.plan(context: context)
        rescue PlanningError => error
          attempt_span.set(:retryable, error.retryable?)
          raise
        end
      end

      span.set(:delegations, delegations.size)

      # O texto das tarefas fica fora da auditoria (só o tamanho): ele vem
      # do LLM a partir do objetivo do usuário.
      audit(run_id, "delegation.planned", "allowed",
            delegations: delegations.map { |d| { id: d.id, agent: d.agent, inputs: d.inputs, task_chars: d.task.length } })

      delegations
    end

    def audit_failure(run_id, error)
      details = { status: "failed", error_class: (error.cause || error).class.name }
      details[:stage] = error.stage if error.respond_to?(:stage)
      details[:signals] = error.signals.map(&:to_s) if error.respond_to?(:signals)

      audit(run_id, "supervisor.finished", "failed", **details)
    rescue StandardError => audit_error
      @tracer.log(:warn, event: "agent_audit.record_failed", run_id: run_id, error_class: audit_error.class.name)
    end

    def audit(run_id, event, outcome, **details)
      @audit_trail.record(run_id: run_id, event: event, outcome: outcome, details: details)
    end
  end
end

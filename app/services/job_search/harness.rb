require "securerandom"
require "socket"

module JobSearch
  # Harness: a camada que transforma "rodar um agente" em operação.
  #
  # O código das aulas anteriores sabe PENSAR e AGIR (planejar, delegar,
  # executar ferramentas). O harness cuida do resto:
  #
  # - submit: grava o pedido (AgentRun) e enfileira um job. A mesma
  #   idempotency_key devolve o mesmo run (retry do cliente não duplica).
  # - execute (no job): "claim" atômico do run com lease, para um único
  #   worker executar mesmo que o job seja entregue duas vezes; monta o
  #   Container com um RunCheckpoint (heartbeat, cancelamento e prazo em
  #   cada fronteira de span); grava resultado, métricas e status final.
  # - cancel: pedido cooperativo; o run para no próximo checkpoint.
  # - recover_stale!: runs cujo worker morreu (lease vencido) voltam para
  #   a fila, até MAX_ATTEMPTS.
  # - Falha transitória (provedor fora do ar) -> volta para a fila e o job
  #   tenta de novo (RunRetryable). Falha permanente -> failed.
  #
  # O id do AgentRun é o run_id do trace e da auditoria: do registro no
  # banco se chega direto aos logs e à cadeia de auditoria do run.
  class Harness
    DEFAULT_TIMEOUT_SECONDS = 300
    LEASE_SECONDS = 60
    MAX_ATTEMPTS = 3

    def initialize(
      container_factory: ->(event_logger:, checkpoint:) { Container.new(event_logger: event_logger, checkpoint: checkpoint) },
      enqueue: ->(run) { AgentRunJob.perform_later(run.id) },
      clock: -> { Time.current },
      worker_id: "#{Socket.gethostname}:#{Process.pid}:#{SecureRandom.hex(4)}",
      lease_seconds: LEASE_SECONDS,
      check_interval: 1.0,
      log_to: Rails.logger
    )
      @container_factory = container_factory
      @enqueue = enqueue
      @clock = clock
      @worker_id = worker_id
      @lease_seconds = lease_seconds
      @check_interval = check_interval
      @log_to = log_to
    end

    def submit(objective:, mode: "agent", idempotency_key: SecureRandom.uuid, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
      run = AgentRun.create_or_find_by!(idempotency_key: idempotency_key) do |record|
        record.mode = mode.to_s
        record.objective = objective
        record.deadline_at = @clock.call + timeout_seconds
      end

      if run.mode != mode.to_s || run.objective != objective
        raise IdempotencyKeyConflict, "Idempotency key #{idempotency_key} was already used for a different request"
      end

      @enqueue.call(run) if run.previously_new_record?
      run
    end

    def cancel(run_id)
      now = @clock.call
      AgentRun.where(id: run_id, cancel_requested_at: nil).update_all(cancel_requested_at: now, updated_at: now)
      # Ainda na fila: cancela na hora. Rodando: para no próximo checkpoint.
      AgentRun.where(id: run_id, status: "queued").update_all(status: "cancelled", finished_at: now, updated_at: now)
      AgentRun.find(run_id)
    end

    # Soft delete: só runs terminados (um run ativo precisa ser cancelado
    # antes). O run some das listas, mas dados, memória e auditoria ficam,
    # e a exclusão entra na cadeia de auditoria do próprio run.
    def delete(run_id)
      run = AgentRun.find(run_id)
      raise ArgumentError, "Cancele o run antes de excluir." unless run.finished?
      return run if run.deleted?

      run.update!(deleted_at: @clock.call)
      audit_trail.record(run_id: run.id, event: "run.deleted", outcome: "info")
      run
    end

    def restore(run_id)
      run = AgentRun.find(run_id)
      return run unless run.deleted?

      run.update!(deleted_at: nil)
      audit_trail.record(run_id: run.id, event: "run.restored", outcome: "info")
      run
    end

    # Chamado pelo AgentRunJob. Devolve o AgentRun, ou nil se outro
    # worker já cuida dele (ou se ele já terminou).
    def execute(run_id)
      run = claim(run_id)
      return nil unless run
      return finish(run, "cancelled", error: RunCancelled.new) if run.cancel_requested?
      return finish(run, "failed", error: RunDeadlineExceeded.new) if run.deadline_at && @clock.call > run.deadline_at

      perform(run)
    end

    def recover_stale!
      AgentRun.where(status: "running").where(locked_until: ...@clock.call).find_each.filter_map do |run|
        if run.attempts >= MAX_ATTEMPTS
          finish(run, "failed", error: RunLeaseLost.new, guard: { locked_by: run.locked_by })
        elsif requeue(run, guard: { locked_by: run.locked_by })
          @enqueue.call(run)
          run.reload
        end
      end
    end

    private

    def audit_trail
      @audit_trail ||= AuditTrail.new
    end

    # Claim atômico: um UPDATE condicional decide quem executa. Só um
    # worker consegue mudar queued -> running (ou assumir um lease vencido).
    def claim(run_id)
      now = @clock.call
      claimed = AgentRun
        .where(id: run_id)
        .where("status = 'queued' OR (status = 'running' AND locked_until < ?)", now)
        .update_all([
          "status = 'running', locked_by = ?, locked_until = ?, attempts = attempts + 1, " \
          "started_at = COALESCE(started_at, ?), updated_at = ?",
          @worker_id, now + @lease_seconds, now, now
        ])

      claimed.zero? ? nil : AgentRun.find(run_id)
    end

    def perform(run)
      collector = Observability::EventCollector.new(forward_to: @log_to)
      checkpoint = RunCheckpoint.new(
        run_id: run.id, worker_id: @worker_id, lease_seconds: @lease_seconds,
        deadline_at: run.deadline_at, check_interval: @check_interval, clock: @clock
      )
      container = @container_factory.call(event_logger: collector.event_logger, checkpoint: checkpoint)

      outcome = run_mode(container, run)
      finish(run, outcome[:status], result: outcome[:result], metrics: metrics(collector))
    rescue StandardError => error
      handle_failure(run, root_cause(error), metrics(collector))
    end

    def run_mode(container, run)
      case run.mode
      when "agent"
        state = container.agent(objective: run.objective).run(run_id: run.id)
        { status: state.status.to_s, result: { output: AgentOutput.from(state) } }
      else
        team = run.mode == "pipeline" ? container.pipeline : container.supervisor
        result = team.run(objective: run.objective, run_id: run.id)
        # Lista (não hash): o jsonb do PostgreSQL reordena chaves de objeto,
        # e a ordem das delegações importa.
        { status: result.status.to_s,
          result: { output: result.output&.value,
                    agents: result.agent_run_ids.map { |delegation, run_id| { delegation: delegation, run_id: run_id } } } }
      end
    end

    def handle_failure(run, error, metrics)
      case error
      when RunLeaseLost
        nil # outro worker é o dono agora: não gravar nada
      when RunCancelled
        finish(run, "cancelled", error: error, metrics: metrics)
      when LlmProviderError
        retry_or_fail(run, error, metrics, transient: error.transient?)
      else
        finish(run, "failed", error: error, metrics: metrics)
      end
    end

    def retry_or_fail(run, error, metrics, transient:)
      return finish(run, "failed", error: error, metrics: metrics) unless transient && run.attempts < MAX_ATTEMPTS

      requeue(run, guard: { locked_by: @worker_id })
      raise RunRetryable, "Run #{run.id} hit a transient error (#{error.class.name}); will retry"
    end

    # Toda escrita final exige que o run ainda seja deste worker (fencing):
    # um worker "zumbi" que perdeu o lease não sobrescreve o resultado.
    def finish(run, status, result: nil, metrics: nil, error: nil, guard: { locked_by: @worker_id })
      now = @clock.call
      attributes = { status: status, finished_at: now, updated_at: now, locked_by: nil, locked_until: nil,
                     error_class: error&.class&.name }
      attributes[:result] = result if result
      attributes[:metrics] = metrics if metrics.present?

      updated = AgentRun.where(id: run.id, **guard).where.not(status: AgentRun::FINAL_STATUSES)
                        .update_all(attributes)
      log("harness.run_finished", run, status: status, error_class: error&.class&.name) if updated.positive?
      run.reload
    end

    def requeue(run, guard:)
      now = @clock.call
      AgentRun.where(id: run.id, status: "running", **guard)
              .update_all(status: "queued", locked_by: nil, locked_until: nil, updated_at: now)
              .positive?
    end

    def root_cause(error)
      error = error.cause while error.is_a?(PipelineStageError) && error.cause
      error
    end

    def metrics(collector)
      collector&.last("run.metrics")&.except("event", "timestamp") || {}
    end

    def log(event, run, **attributes)
      Observability::EventLogger.new(logger: @log_to).info(event: event, run_id: run.id, mode: run.mode, **attributes.compact)
    end
  end
end

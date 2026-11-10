module JobSearch
  # Checkpoint cooperativo do harness, chamado pelo Tracer antes de cada
  # span começar (llm.call, step, delegation...). Ali é seguro parar: nada
  # é interrompido no meio de uma chamada de ferramenta ou de LLM.
  #
  # Em cada checkpoint:
  # - prazo: passou de deadline_at -> RunDeadlineExceeded (sem ir ao banco);
  # - a cada check_interval segundos, uma ida ao banco que:
  #   - renova o lease (heartbeat). Se a linha não é mais deste worker,
  #     -> RunLeaseLost;
  #   - lê cancel_requested_at -> RunCancelled.
  #
  # Thread-safe: agentes em paralelo chamam o mesmo checkpoint.
  class RunCheckpoint
    def initialize(run_id:, worker_id:, lease_seconds:, deadline_at: nil,
                   check_interval: 1.0, clock: -> { Time.current })
      @run_id = run_id
      @worker_id = worker_id
      @lease_seconds = lease_seconds
      @deadline_at = deadline_at
      @check_interval = check_interval
      @clock = clock
      @last_check = nil
      @lock = Mutex.new
    end

    def call(_span_name = nil)
      now = @clock.call
      raise RunDeadlineExceeded, "Run #{@run_id} passed its deadline" if @deadline_at && now > @deadline_at

      @lock.synchronize do
        return if @last_check && (now - @last_check) < @check_interval

        @last_check = now
        heartbeat!(now)
      end
    end

    private

    def heartbeat!(now)
      renewed = AgentRun
        .where(id: @run_id, locked_by: @worker_id, status: "running")
        .update_all(locked_until: now + @lease_seconds, updated_at: now)

      raise RunLeaseLost, "Run #{@run_id} is no longer owned by #{@worker_id}" if renewed.zero?
      raise RunCancelled, "Run #{@run_id} was cancelled" if AgentRun.where(id: @run_id).pick(:cancel_requested_at)
    end
  end
end

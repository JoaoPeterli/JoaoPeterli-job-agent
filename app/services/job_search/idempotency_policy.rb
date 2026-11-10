module JobSearch
  class IdempotencyPolicy
    class OperationInProgress < StandardError; end
    class CompletionFailed < StandardError; end

    # O worker perdeu o lease durante a execução (outro worker assumiu ou
    # a operação mudou de estado). O resultado não foi gravado.
    class LeaseLost < CompletionFailed; end

    # heartbeat_interval: quando presente, o lease é renovado nesse
    # intervalo (em segundos) enquanto a operação executa. Deve ser
    # menor que o TTL do store.
    def initialize(store:, recover_expired: true, heartbeat_interval: nil)
      @store = store
      @recover_expired = recover_expired
      @heartbeat_interval = heartbeat_interval
    end

    # O bloco recebe o Lease adquirido, para que a operação possa enviar
    # lease.key e lease.fencing_token ao recurso externo.
    #
    # side_effects decide o destino da operação quando ela falha com um
    # erro inesperado: com efeito colateral o resultado é desconhecido
    # (uncertain); sem efeito colateral é seguro liberar a chave.
    def call(
      key:,
      recover_expired: @recover_expired,
      operation_type: nil,
      side_effects: true
    )
      if @store.completed?(key)
        return @store.completed_result(key)
      end

      lease = @store.acquire_lease(
        key,
        recover_expired: recover_expired,
        operation_type: operation_type
      )

      unless lease
        if @store.completed?(key)
          return @store.completed_result(key)
        end

        raise OperationInProgress,
              "Operation #{key} is already in progress"
      end

      result, lease_lost = execute_with_lease(lease, side_effects: side_effects) do
        yield(lease)
      end

      if lease_lost
        raise LeaseLost,
              "Lease lost while executing operation #{key} " \
              "(fencing_token=#{lease.fencing_token})"
      end

      completed = @store.complete(
        key,
        lease.token,
        result: result
      )

      unless completed
        raise CompletionFailed,
              "Could not complete operation #{key}"
      end

      result
    end

    private

    def execute_with_lease(lease, side_effects:, &operation)
      result, lease_lost = with_heartbeat(lease, &operation)

      [ result, lease_lost ]
    rescue JobSearch::ToolTimeoutError, Timeout::Error
      # Resultado desconhecido: a operação pode ter tido efeito.
      unless @store.mark_uncertain(lease.key, lease.token)
        Rails.logger.error(
          "Could not mark uncertain operation: #{lease.key}"
        )
      end

      raise
    rescue JobSearch::PermanentError
      # Contrato de PermanentError: a operação foi rejeitada e não teve
      # efeito. É seguro liberar a chave para uma nova tentativa. Se este
      # worker já for obsoleto, o release é recusado (compare-and-set).
      @store.release(lease.key, lease.token)

      raise
    rescue JobSearch::ExecutionBudgetExceeded
      # O budget é verificado antes de cada chamada da ferramenta, então
      # a tentativa recusada não chegou a executar.
      @store.release(lease.key, lease.token)

      raise
    rescue StandardError
      # Erro inesperado (TransientError esgotado, bug, etc.). Sem isso a
      # linha ficaria como "leased" até o TTL e, para ferramentas com
      # efeito colateral (recover_expired: false), nunca mais seria
      # adquirível.
      if side_effects
        unless @store.mark_uncertain(lease.key, lease.token)
          Rails.logger.error(
            "Could not mark uncertain operation: #{lease.key}"
          )
        end
      else
        @store.release(lease.key, lease.token)
      end

      raise
    end

    def with_heartbeat(lease)
      unless @heartbeat_interval
        return [ yield, false ]
      end

      heartbeat = LeaseHeartbeat.new(
        store: @store,
        lease: lease,
        interval: @heartbeat_interval
      ).start

      begin
        result = yield
      ensure
        heartbeat.stop
      end

      # Lido só depois do stop: nenhuma renovação pode estar em andamento.
      [ result, heartbeat.lost? ]
    end
  end
end

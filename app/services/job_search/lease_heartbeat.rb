module JobSearch
  # Renova periodicamente um lease de execução enquanto a operação roda.
  #
  # Sem heartbeat, uma operação mais longa que o TTL perde o lease no meio
  # da execução, e outro worker pode assumi-la. Com heartbeat, o lease só
  # expira se o worker realmente parar (crash, pausa longa, partição de
  # rede), que é exatamente o caso em que ele deve ser considerado obsoleto.
  #
  # Quando uma renovação é recusada pelo store, o lease foi perdido: outro
  # worker assumiu ou a operação mudou de estado. O heartbeat para e
  # #lost? passa a retornar true. O dono deve então abandonar a operação
  # sem gravar resultado.
  #
  # O intervalo deve ser bem menor que o TTL (recomendado: TTL / 3), para
  # tolerar uma ou duas renovações atrasadas.
  class LeaseHeartbeat
    def initialize(store:, lease:, interval:, logger: Rails.logger)
      raise ArgumentError, "interval must be positive" unless interval.positive?

      @store = store
      @lease = lease
      @interval = interval
      @logger = logger
      @stop_signal = Queue.new
      @lost = false
      @renewals = 0
    end

    attr_reader :renewals

    def lost?
      @lost
    end

    def start
      raise "Heartbeat already started" if @thread

      @thread = Thread.new { beat }
      @thread.name = "lease-heartbeat:#{@lease.key}" if @thread.respond_to?(:name=)

      self
    end

    def stop
      return unless @thread

      @stop_signal << :stop
      @thread.join
      @thread = nil
    end

    private

    def beat
      loop do
        # pop com timeout funciona como um sleep interrompível.
        break if @stop_signal.pop(timeout: @interval) == :stop

        break unless renew
      end
    ensure
      # A renovação pode ter usado uma conexão própria desta thread.
      ActiveRecord::Base.connection_pool.release_connection
    end

    # Retorna false quando o heartbeat deve parar.
    def renew
      if @store.renew(@lease.key, @lease.token)
        @renewals += 1
        return true
      end

      @lost = true

      @logger.warn(
        "[JobSearch::LeaseHeartbeat] Lease lost for key=#{@lease.key} " \
        "fencing_token=#{@lease.fencing_token}"
      )

      false
    rescue StandardError => error
      # Falha transitória (ex.: banco indisponível). Não sabemos se o
      # lease foi perdido; continuamos tentando. Se ele expirar de fato,
      # a escrita final (compare-and-set) será recusada.
      @logger.error(
        "[JobSearch::LeaseHeartbeat] Renewal failed for key=#{@lease.key}: " \
        "#{error.class}: #{error.message}"
      )

      true
    end
  end
end

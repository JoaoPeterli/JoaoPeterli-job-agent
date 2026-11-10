require "timeout"

module JobSearch
  # Utilitários para testes de corrida contra o PostgreSQL.
  #
  # Os specs que usam estes helpers precisam desligar as transações de
  # teste (self.use_transactional_tests = false). Com transações ligadas,
  # o Rails faz todas as threads compartilharem a mesma conexão, e as
  # "corridas" passam a ser executadas em série, sem disputa real.
  module ConcurrencyHelpers
    # Executa o bloco em `count` threads. Cada thread usa a própria
    # conexão com o banco e todas são liberadas juntas por uma barreira,
    # maximizando a disputa. Retorna os valores na ordem das threads.
    #
    # Exceções inesperadas dentro das threads são propagadas.
    def run_concurrently(count, timeout: 10)
      pool_size = ActiveRecord::Base.connection_pool.size

      if count >= pool_size
        raise ArgumentError,
              "#{count} workers need #{count + 1} connections; pool has #{pool_size}"
      end

      ready = Queue.new
      start = Queue.new

      threads = Array.new(count) do |index|
        Thread.new do
          Thread.current.report_on_exception = false

          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop

            yield index
          end
        end
      end

      Timeout.timeout(timeout) do
        count.times { ready.pop }
        count.times { start << true }

        threads.map(&:value)
      end
    ensure
      threads&.each do |thread|
        thread.kill if thread.alive?
        thread.join
      rescue StandardError
        nil
      end
    end

    # Executa o bloco capturando a exceção como valor, para que o teste
    # possa verificar o desfecho de cada worker.
    def capture_outcome
      yield
    rescue StandardError => error
      error
    end

    def operation_row(key)
      JobSearchOperation.find_by!(operation_key: key)
    end

    def expire_lease!(key)
      JobSearchOperation
        .where(operation_key: key)
        .update_all(expires_at: 1.second.ago)
    end
  end
end

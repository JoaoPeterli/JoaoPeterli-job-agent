require "securerandom"

module JobSearch
  # Store de idempotência em memória, com a mesma semântica de
  # PostgresIdempotencyStore (usado em testes e no Container local).
  #
  # Não é thread-safe: para múltiplos workers use o store do PostgreSQL.
  class IdempotencyStore
    def initialize(ttl_seconds: 30, clock: Clock.new)
      raise ArgumentError, "TTL must be positive" unless ttl_seconds.positive?

      @ttl_seconds = ttl_seconds
      @clock = clock
      @operations = {}
      @fencing_tokens = Hash.new(0)
    end

    # Compatibilidade: retorna apenas o token da aquisição.
    def acquire(key, recover_expired: true, operation_type: nil)
      acquire_lease(
        key,
        recover_expired: recover_expired,
        operation_type: operation_type
      )&.token
    end

    def acquire_lease(key, recover_expired: true, operation_type: nil)
      now = @clock.now
      operation = @operations[key]

      return nil unless acquirable?(operation, now, recover_expired)

      token = SecureRandom.uuid
      fencing_token = @fencing_tokens[key] += 1

      @operations[key] = {
        status: :leased,
        token: token,
        expires_at: now + @ttl_seconds
      }

      Lease.new(key: key, token: token, fencing_token: fencing_token)
    end

    def renew(key, token)
      now = @clock.now
      operation = @operations[key]

      return false unless valid_lease?(operation, token, now)

      operation[:expires_at] = now + @ttl_seconds

      true
    end

    def valid?(key, token)
      valid_lease?(@operations[key], token, @clock.now)
    end

    # Devolve a operação para um estado adquirível. O fencing token
    # é preservado para continuar monotônico.
    def release(key, token)
      now = @clock.now
      operation = @operations[key]

      return false unless valid_lease?(operation, token, now)

      @operations[key] = { status: :released }

      true
    end

    def complete(key, token, result:)
      now = @clock.now
      operation = @operations[key]

      return false unless valid_lease?(operation, token, now)

      @operations[key] = {
        status: :completed,
        result: result
      }

      true
    end

    def completed?(key)
      operation = @operations[key]

      return false unless operation

      operation[:status] == :completed
    end

    def completed_result(key)
      operation = @operations[key]

      return nil unless operation
      return nil unless operation[:status] == :completed

      operation[:result]
    end

    def mark_uncertain(key, token)
      now = @clock.now
      operation = @operations[key]

      return false unless valid_lease?(operation, token, now)

      @operations[key] = {
        status: :uncertain,
        token: token,
        marked_at: now
      }

      true
    end

    def reconcile_completed(key, result:)
      operation = @operations[key]

      return false unless operation
      return false unless operation[:status] == :uncertain

      @operations[key] = {
        status: :completed,
        result: result
      }

      true
    end

    private

    def acquirable?(operation, now, recover_expired)
      return true if operation.nil?
      return true if operation[:status] == :released

      # completed, uncertain e qualquer outro estado terminal
      # nunca são adquiridos novamente.
      return false unless operation[:status] == :leased

      # Outro worker ainda possui um lease válido.
      return false if now < operation[:expires_at]

      # Lease expirado: só recuperamos quando a política permitir.
      recover_expired
    end

    def valid_lease?(operation, token, now)
      return false unless operation
      return false unless operation[:status] == :leased
      return false unless operation[:token] == token
      return false if now >= operation[:expires_at]

      true
    end
  end
end

require "securerandom"

module JobSearch
  # Store de idempotência baseado em PostgreSQL.
  #
  # Garantias de concorrência:
  #
  # - Toda transição de estado é uma única instrução SQL condicional
  #   (compare-and-set). Não há janela entre "ler" e "escrever".
  # - Toda escrita feita pelo dono do lease exige o lease_token atual
  #   e um lease ainda válido. Um worker obsoleto nunca sobrescreve o
  #   estado de quem assumiu a operação depois dele.
  # - Cada aquisição incrementa fencing_token. O valor nunca diminui,
  #   nem mesmo após release, para que recursos externos possam
  #   rejeitar escritas de workers obsoletos.
  class PostgresIdempotencyStore
    ACQUIRABLE_RELEASED = "released".freeze

    def initialize(ttl_seconds: 30)
      raise ArgumentError, "TTL must be positive" unless ttl_seconds.positive?

      @ttl_seconds = ttl_seconds
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
      operation_type = operation_type&.to_s
      token = SecureRandom.uuid

      fencing_token = insert_new_lease(key, token, operation_type)

      if fencing_token
        return Lease.new(key: key, token: token, fencing_token: fencing_token)
      end

      ensure_operation_type!(key, operation_type)

      fencing_token = take_over_lease(
        key,
        token,
        recover_expired: recover_expired
      )

      return nil unless fencing_token

      Lease.new(key: key, token: token, fencing_token: fencing_token)
    end

    def renew(key, token)
      now = Time.current

      owned_by(key, token, now).update_all(
        expires_at: now + @ttl_seconds,
        updated_at: now
      ) == 1
    end

    def valid?(key, token)
      owned_by(key, token, Time.current).exists?
    end

    def complete(key, token, result:)
      now = Time.current

      owned_by(key, token, now).update_all(
        status: "completed",
        result: result,
        lease_token: nil,
        expires_at: nil,
        updated_at: now
      ) == 1
    end

    # Devolve a operação para um estado adquirível sem apagar a linha.
    # Apagar reiniciaria o fencing_token e quebraria a monotonicidade.
    def release(key, token)
      now = Time.current

      owned_by(key, token, now).update_all(
        status: ACQUIRABLE_RELEASED,
        lease_token: nil,
        expires_at: nil,
        updated_at: now
      ) == 1
    end

    def mark_uncertain(key, token)
      now = Time.current

      owned_by(key, token, now).update_all(
        status: "uncertain",
        lease_token: nil,
        expires_at: nil,
        updated_at: now
      ) == 1
    end

    def reconcile_completed(key, result:, reconciliation_token: nil)
      now = Time.current

      scope = JobSearchOperation.where(
        operation_key: key,
        status: "uncertain"
      )

      if reconciliation_token.present?
        scope = scope
          .where(reconciliation_token: reconciliation_token)
          .where("reconciliation_expires_at > ?", now)
      else
        # Compatibilidade temporária com operações anteriores.
        # Não permite ignorar um lease de reconciliação existente.
        scope = scope.where(reconciliation_token: nil)
      end

      scope.update_all(
        status: "completed",
        result: result,
        lease_token: nil,
        expires_at: nil,
        reconciliation_token: nil,
        reconciliation_expires_at: nil,
        next_reconciliation_at: nil,
        updated_at: now
      ) == 1
    end

    def completed?(key)
      JobSearchOperation.exists?(
        operation_key: key,
        status: "completed"
      )
    end

    def completed_result(key)
      JobSearchOperation
        .where(operation_key: key, status: "completed")
        .pick(:result)
    end

    private

    def owned_by(key, token, now)
      JobSearchOperation
        .where(operation_key: key, status: "leased", lease_token: token)
        .where("expires_at > ?", now)
    end

    # INSERT ... ON CONFLICT DO NOTHING RETURNING fencing_token.
    # Retorna o fencing token quando esta chamada criou a operação.
    def insert_new_lease(key, token, operation_type)
      now = Time.current

      result = JobSearchOperation.insert_all(
        [
          {
            operation_key: key,
            status: "leased",
            lease_token: token,
            expires_at: now + @ttl_seconds,
            operation_type: operation_type,
            fencing_token: 1,
            created_at: now,
            updated_at: now
          }
        ],
        unique_by: :operation_key,
        returning: [ :fencing_token ]
      )

      row = result.rows.first

      row && Integer(row.first)
    end

    # Uma chave existente nunca pode ser reutilizada
    # silenciosamente para outro tipo de operação.
    def ensure_operation_type!(key, operation_type)
      return unless operation_type

      existing_type = JobSearchOperation
        .where(operation_key: key)
        .pick(:operation_type)

      return if existing_type.nil? || existing_type == operation_type

      raise ArgumentError,
            "Operation type mismatch for key=#{key}"
    end

    # Assume a operação com um único UPDATE atômico. Se vários workers
    # disputarem a mesma linha, o PostgreSQL serializa as escritas e
    # apenas o primeiro ainda encontra a condição do WHERE verdadeira.
    #
    # Pode ser assumida:
    # - uma operação liberada (status released), sempre;
    # - um lease expirado, apenas quando recover_expired for verdadeiro.
    #
    # Nunca são assumidas: completed, uncertain e needs_review.
    def take_over_lease(key, token, recover_expired:)
      now = Time.current

      sql = JobSearchOperation.sanitize_sql_array(
        [
          <<~SQL.squish,
            UPDATE job_search_operations
            SET status = 'leased',
                lease_token = :token,
                expires_at = :expires_at,
                fencing_token = fencing_token + 1,
                updated_at = :now
            WHERE operation_key = :key
              AND (
                status = :released
                OR (
                  :recover_expired
                  AND status = 'leased'
                  AND expires_at <= :now
                )
              )
            RETURNING fencing_token
          SQL
          {
            token: token,
            expires_at: now + @ttl_seconds,
            now: now,
            key: key,
            released: ACQUIRABLE_RELEASED,
            recover_expired: recover_expired ? true : false
          }
        ]
      )

      # exec_query (e não select_value): select_* pode ser servido pelo
      # query cache, e um UPDATE ... RETURNING precisa sempre executar.
      value = JobSearchOperation.connection.exec_query(
        sql,
        "JobSearch take over lease"
      ).rows.first&.first

      value && Integer(value)
    end
  end
end

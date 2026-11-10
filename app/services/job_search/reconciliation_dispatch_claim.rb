
module JobSearch
  class ReconciliationDispatchClaim
    def initialize(ttl_seconds: 60)
      raise ArgumentError, "ttl_seconds must be positive" unless ttl_seconds.positive?

      @ttl_seconds = ttl_seconds
    end

    def acquire(key)
      now = Time.current
      token = SecureRandom.uuid

      updated = JobSearchOperation
        .where(operation_key: key, status: "uncertain")
        .where.not(operation_type: [ nil, "" ])
        .where(
          "next_reconciliation_at IS NULL OR next_reconciliation_at <= ?",
          now
        )
        .where(
          "reconciliation_expires_at IS NULL OR reconciliation_expires_at <= ?",
          now
        )
        .where(
          "reconciliation_dispatch_expires_at IS NULL OR reconciliation_dispatch_expires_at <= ?",
          now
        )
        .update_all(
          reconciliation_dispatch_token: token,
          reconciliation_dispatch_expires_at: now + @ttl_seconds,
          updated_at: now
        )

      updated == 1 ? token : nil
    end

    def release(key, token)
      return false if token.blank?

      updated = JobSearchOperation
        .where(
          operation_key: key,
          reconciliation_dispatch_token: token
        )
        .update_all(
          reconciliation_dispatch_token: nil,
          reconciliation_dispatch_expires_at: nil,
          updated_at: Time.current
        )

      updated == 1
    end
  end
end

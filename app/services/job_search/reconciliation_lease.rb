
require "securerandom"

module JobSearch
  class ReconciliationLease
    def initialize(ttl_seconds: 30)
      raise ArgumentError, "TTL must be positive" unless ttl_seconds.positive?

      @ttl_seconds = ttl_seconds
    end

    def acquire(key)
      token = SecureRandom.uuid
      now = Time.current

      updated = JobSearchOperation
        .where(
          operation_key: key,
          status: "uncertain"
        )
        .where(
          "next_reconciliation_at IS NULL OR next_reconciliation_at <= ?",
          now
        )
        .where(
          "reconciliation_expires_at IS NULL OR reconciliation_expires_at <= ?",
          now
        )
        .update_all(
          [
            <<~SQL.squish,
              reconciliation_token = ?,
              reconciliation_expires_at = ?,
              reconciliation_attempts = reconciliation_attempts + 1,
              updated_at = ?
            SQL
            token,
            now + @ttl_seconds,
            now
          ]
        )

      updated == 1 ? token : nil
    end


def release(key, token)
  return false if token.blank?

  now = Time.current

  updated = JobSearchOperation
    .where(
      operation_key: key,
      status: "uncertain",
      reconciliation_token: token
    )
    .where(
      "reconciliation_expires_at > ?",
      now
    )
    .update_all(
      reconciliation_token: nil,
      reconciliation_expires_at: nil,
      updated_at: now
    )

  updated == 1
end



def valid?(key, token)
  return false if token.blank?

  JobSearchOperation
    .where(
      operation_key: key,
      status: "uncertain",
      reconciliation_token: token
    )
    .where(
      "reconciliation_expires_at > ?",
      Time.current
    )
    .exists?
end



def renew(key, token)
  return false if token.blank?

  now = Time.current

  updated = JobSearchOperation
    .where(
      operation_key: key,
      status: "uncertain",
      reconciliation_token: token
    )
    .where(
      "reconciliation_expires_at > ?",
      now
    )
    .update_all(
      reconciliation_expires_at: now + @ttl_seconds,
      updated_at: now
    )

  updated == 1
end
  end
end

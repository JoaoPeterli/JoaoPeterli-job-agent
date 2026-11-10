
module JobSearch
  class ReconciliationScheduler
    MAX_ATTEMPTS = 5

    def initialize(backoff: ReconciliationBackoff.new)
      @backoff = backoff
    end

    def schedule_next(key:, reconciliation_token:)
      return false if reconciliation_token.blank?

      JobSearchOperation.transaction do
        operation = JobSearchOperation
          .where(operation_key: key)
          .lock
          .first

        return false unless operation
        return false unless operation.status == "uncertain"

        return false unless operation.reconciliation_token ==
                            reconciliation_token

        now = Time.current

        return false unless operation.reconciliation_expires_at &&
                            operation.reconciliation_expires_at > now

        if operation.reconciliation_attempts >= MAX_ATTEMPTS
          operation.update!(
            status: "needs_review",
            next_reconciliation_at: nil,
            reconciliation_token: nil,
            reconciliation_expires_at: nil,
            reconciliation_dispatch_token: nil,
            reconciliation_dispatch_expires_at: nil
          )

          return true
        end

        delay = @backoff.delay_for(
          operation.reconciliation_attempts
        )

        operation.update!(
          next_reconciliation_at: now + delay
        )

        true
      end
    end
  end
end

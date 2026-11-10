
module JobSearch
  class ReconciliationDispatcher
    def initialize(
      claim: ReconciliationDispatchClaim.new
    )
      @claim = claim
    end

    def call
      now = Time.current
      dispatched = 0

      eligible_operations(now).find_each do |operation|
        key = operation.operation_key

        token = @claim.acquire(key)

        next unless token

        begin
          job = ReconciliationJob.perform_later(key, token)

          unless job
            @claim.release(key, token)
            next
          end

          dispatched += 1
        rescue StandardError
          @claim.release(key, token)
          raise
        end
      end

      dispatched
    end

    private

    def eligible_operations(now)
      JobSearchOperation
        .where(status: "uncertain")
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
    end
  end
end

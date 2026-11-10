
module JobSearch
  class StaleOperationRecoveryService
    def call
      now = Time.current

      JobSearchOperation
        .where(status: "leased")
        .where("expires_at <= ?", now)
        .where.not(operation_type: [ nil, "" ])
        .update_all(
          status: "uncertain",
          lease_token: nil,
          expires_at: nil,
          updated_at: now
        )
    end
  end
end

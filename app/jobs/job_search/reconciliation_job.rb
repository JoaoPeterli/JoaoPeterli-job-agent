
module JobSearch
  class ReconciliationJob < ApplicationJob
    queue_as :default

    def perform(key, dispatch_token = nil)
      release_dispatch_claim = false

      operation = JobSearchOperation.find_by(
        operation_key: key
      )

      unless operation
        release_dispatch_claim = true
        return nil
      end

      if operation.status == "completed"
        release_dispatch_claim = true
        return nil
      end

      return nil unless operation.status == "uncertain"

      if operation.operation_type.blank?
        Rails.logger.warn(
          "[JobSearch::ReconciliationJob] " \
          "Missing operation_type for key=#{key}"
        )

        release_dispatch_claim = true
        return nil
      end

      lease = ReconciliationLease.new(ttl_seconds: 30)
      reconciliation_token = lease.acquire(key)

      return nil unless reconciliation_token

      release_dispatch_claim = true

      begin
        container = ReconciliationContainer.configured

        service = container.build(
          operation_type: operation.operation_type
        )

        service.call(
          key: key,
          reconciliation_token: reconciliation_token
        )
      ensure
        lease.release(key, reconciliation_token)
      end
    ensure
      if dispatch_token.present? && release_dispatch_claim
        ReconciliationDispatchClaim.new.release(
          key,
          dispatch_token
        )
      end
    end
  end
end

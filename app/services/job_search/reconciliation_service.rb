
module JobSearch
  class ReconciliationService
    def initialize(
      store:,
      checker:,
      scheduler: ReconciliationScheduler.new
    )
      @store = store
      @checker = checker
      @scheduler = scheduler
    end

    def call(key:, reconciliation_token:)
      response = @checker.call(key: key)

      case response.fetch(:status)
      when :confirmed
        result = response.fetch(:result)

        reconciled = @store.reconcile_completed(
          key,
          result: result,
          reconciliation_token: reconciliation_token
        )

        return nil unless reconciled

        result

      when :unknown, :not_found
        @scheduler.schedule_next(
          key: key,
          reconciliation_token: reconciliation_token
        )

        nil

      else
        raise ArgumentError,
              "Unsupported reconciliation status: #{response[:status]}"
      end

    rescue Timeout::Error => error
      Rails.logger.warn(
        "[JobSearch::ReconciliationService] " \
        "Reconciliation timed out for key=#{key}: " \
        "#{error.class}"
      )

      schedule_after_failure(key, reconciliation_token)

      nil
    rescue StandardError => error
      Rails.logger.error(
        "[JobSearch::ReconciliationService] " \
        "Reconciliation failed for key=#{key}: " \
        "#{error.class}: #{error.message}"
      )

      schedule_after_failure(key, reconciliation_token)

      raise
    end

    private

    # Uma falha na verificação também conta como tentativa: sem isso a
    # operação voltaria a ser elegível no próximo tick (sem backoff) e
    # nunca chegaria a needs_review enquanto a API externa estiver fora.
    def schedule_after_failure(key, reconciliation_token)
      @scheduler.schedule_next(
        key: key,
        reconciliation_token: reconciliation_token
      )
    rescue StandardError => error
      Rails.logger.error(
        "[JobSearch::ReconciliationService] " \
        "Could not schedule next reconciliation for key=#{key}: " \
        "#{error.class}: #{error.message}"
      )
    end
  end
end

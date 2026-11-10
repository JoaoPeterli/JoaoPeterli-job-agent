
module JobSearch
  class ApplicationsReconciliationChecker
    def initialize(client:)
      @client = client
    end

    def call(key:)
      result = @client.find_by_idempotency_key(
        idempotency_key: key
      )

      if result.nil?
        return { status: :not_found }
      end

      {
        status: :confirmed,
        result: result
      }
    rescue Timeout::Error
      { status: :unknown }
    end
  end
end

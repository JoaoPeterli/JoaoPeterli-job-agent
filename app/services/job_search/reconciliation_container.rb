
module JobSearch
  class ReconciliationContainer
    def self.configured
      registry = Rails.configuration.x.job_search_reconciliation_registry

      unless registry
        raise ArgumentError,
              "Reconciliation registry is not configured"
      end

      new(registry: registry)
    end

    def initialize(registry:, store: nil)
      @registry = registry
      @store = store
    end

    def build(operation_type:)
      factory.build(operation_type: operation_type)
    end

    private

    def factory
      @factory ||= ReconciliationServiceFactory.new(
        registry: @registry,
        store: @store
      )
    end
  end
end

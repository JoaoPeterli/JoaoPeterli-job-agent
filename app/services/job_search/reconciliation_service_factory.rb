
module JobSearch
  class ReconciliationServiceFactory
    def initialize(checker: nil, registry: nil, store: nil)
      if checker && registry
        raise ArgumentError,
              "Provide either checker or registry, not both"
      end

      if checker.nil? && registry.nil?
        raise ArgumentError,
              "A checker or registry is required"
      end

      @checker = checker
      @registry = registry
      @store = store
    end

    def build(operation_type: nil)
      selected_checker = resolve_checker(operation_type)

      ReconciliationService.new(
        store: @store || PostgresIdempotencyStore.new,
        checker: selected_checker
      )
    end

    private

    def resolve_checker(operation_type)
      return @checker if @checker

      if operation_type.nil? ||
         operation_type.to_s.strip.empty?
        raise ArgumentError,
              "operation_type is required when using registry"
      end

      @registry.fetch(operation_type)
    end
  end
end

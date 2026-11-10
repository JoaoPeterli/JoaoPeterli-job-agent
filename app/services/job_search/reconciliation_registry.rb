
module JobSearch
  class ReconciliationRegistry
    def initialize
      @checkers = {}
    end

    def register(operation_type, checker)
      key = operation_type.to_sym

      if @checkers.key?(key)
        raise ArgumentError,
              "Checker already registered: #{key}"
      end

      @checkers[key] = checker
    end

    def fetch(operation_type)
      key = operation_type.to_sym

      @checkers.fetch(key) do
        raise KeyError,
              "Unknown reconciliation checker: #{key}"
      end
    end
  end
end

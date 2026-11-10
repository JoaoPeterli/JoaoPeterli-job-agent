module JobSearch
  module Observability
    # Tracer que não registra nada. Padrão dos componentes internos
    # quando usados fora do Container (ex.: testes unitários).
    class NullTracer
      class NullSpan
        def set(_key, _value)
          self
        end

        def trace_id = nil
        def span_id = nil
      end

      NULL_SPAN = NullSpan.new

      def span(_name, **_attributes)
        yield NULL_SPAN
      end

      def current_span
        nil
      end

      def attach(_parent)
        yield
      end

      def log(_level, event:, **_attributes); end
    end
  end
end

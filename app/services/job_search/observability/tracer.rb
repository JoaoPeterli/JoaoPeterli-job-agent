require "securerandom"

module JobSearch
  module Observability
    # Rastreamento de um run do agente, gravado como logs estruturados.
    #
    # trace = um run (trace_id = run_id); span = uma etapa com início,
    # fim, duração e pai. Cada span é emitido como um evento "span" ao
    # terminar, e todo log feito com #log carrega trace_id e span_id do
    # span corrente, para correlacionar eventos do mesmo run.
    #
    # Privacidade: atributos devem ser metadados (tamanhos, contagens,
    # nomes, classes de erro), nunca prompt, objetivo ou dados de
    # ferramentas.
    #
    # listeners: objetos com #call(span_hash), chamados a cada span
    # terminado (ex.: RunMetrics). Uma falha no listener é registrada e
    # ignorada: métrica nunca derruba um run.
    #
    # Um Tracer pertence a um único run (ou time de agentes). É seguro
    # entre threads: cada thread tem a própria pilha de spans, e um
    # worker usa #attach para pendurar os spans dele no span do
    # coordinador que o disparou (Aula 43).
    class Tracer
      class Span
        attr_reader :trace_id, :span_id, :parent_span_id, :name, :attributes

        def initialize(trace_id:, span_id:, parent_span_id:, name:, attributes:)
          @trace_id = trace_id
          @span_id = span_id
          @parent_span_id = parent_span_id
          @name = name
          @attributes = attributes
        end

        def set(key, value)
          @attributes[key] = value
          self
        end
      end

      def initialize(
        event_logger: EventLogger.new,
        clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond) },
        id_generator: -> { SecureRandom.hex(8) },
        listeners: []
      )
        @event_logger = event_logger
        @listeners = listeners
        @clock = clock
        @id_generator = id_generator
        @stacks = {}
        @lock = Mutex.new
      end

      def current_span
        stack.last
      end

      # Roda o bloco com `parent` como span corrente desta thread, sem
      # emiti-lo de novo: é o elo entre o span do coordenador e os spans
      # criados dentro de uma thread worker.
      def attach(parent)
        return yield if parent.nil? || current_span.equal?(parent)

        stack.push(parent)
        begin
          yield
        ensure
          stack.pop
          release_stack
        end
      end

      # trace_id só é usado no span raiz; spans filhos herdam o do pai.
      def span(name, trace_id: nil, **attributes)
        parent = current_span
        span = Span.new(
          trace_id: parent&.trace_id || trace_id || @id_generator.call,
          span_id: @id_generator.call,
          parent_span_id: parent&.span_id,
          name: name,
          attributes: attributes
        )

        stack.push(span)
        started_at = @clock.call
        status = "ok"
        error_class = nil

        begin
          yield span
        rescue Exception => error # rubocop:disable Lint/RescueException
          status = "error"
          error_class = error.class.name
          raise
        ensure
          stack.pop
          release_stack
          emit(span, duration_ms: (@clock.call - started_at).round(2), status: status, error_class: error_class)
        end
      end

      def log(level, event:, **attributes)
        @event_logger.public_send(level, event: event, **correlation, **attributes)
      end

      private

      def stack
        @lock.synchronize { @stacks[Thread.current] ||= [] }
      end

      # Thread sem spans abertos não precisa de entrada (evita acumular
      # pilhas de threads que já terminaram).
      def release_stack
        @lock.synchronize do
          @stacks.delete(Thread.current) if @stacks[Thread.current]&.empty?
        end
      end

      def correlation
        span = current_span
        return {} unless span

        { trace_id: span.trace_id, span_id: span.span_id }
      end

      def emit(span, duration_ms:, status:, error_class:)
        payload = {
          event: "span",
          name: span.name,
          trace_id: span.trace_id,
          span_id: span.span_id,
          parent_span_id: span.parent_span_id,
          duration_ms: duration_ms,
          status: status
        }
        payload[:error_class] = error_class if error_class

        level = status == "ok" ? :info : :warn

        payload = payload.merge(span.attributes)
        @event_logger.public_send(level, **payload)
        notify(payload)
      end

      def notify(payload)
        @listeners.each do |listener|
          listener.call(payload)
        rescue StandardError => error
          @event_logger.warn(
            event: "tracer.listener_failed",
            listener: listener.class.name,
            error_class: error.class.name
          )
        end
      end
    end
  end
end

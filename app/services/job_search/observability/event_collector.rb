require "json"

module JobSearch
  module Observability
    # Guarda em memória os eventos estruturados de uma execução, para quem
    # precisa lê-los depois (ex.: o runner de evals lê o "run.metrics").
    # Os eventos passam pelo EventLogger real (mesmo filtro de segredos).
    # Thread-safe.
    class EventCollector
      # forward_to: Logger que também recebe os eventos (ex.: Rails.logger),
      # para coletar sem deixar de logar.
      class Sink
        def initialize(collector, forward_to)
          @collector = collector
          @forward_to = forward_to
        end

        %i[info warn error].each do |level|
          define_method(level) do |message|
            @forward_to&.public_send(level, message)
            @collector.push(JSON.parse(message))
          end
        end
      end

      attr_reader :event_logger

      def initialize(forward_to: nil)
        @events = []
        @lock = Mutex.new
        @event_logger = EventLogger.new(logger: Sink.new(self, forward_to))
      end

      def push(event)
        @lock.synchronize { @events << event }
      end

      def events
        @lock.synchronize { @events.dup }
      end

      def last(name)
        events.reverse.find { |event| event["event"] == name }
      end
    end
  end
end

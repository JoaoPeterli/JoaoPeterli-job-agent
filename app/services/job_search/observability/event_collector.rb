require "json"

module JobSearch
  module Observability
    # Guarda em memória os eventos estruturados de uma execução, para quem
    # precisa lê-los depois (ex.: o runner de evals lê o "run.metrics").
    # Os eventos passam pelo EventLogger real (mesmo filtro de segredos).
    # Thread-safe.
    class EventCollector
      class Sink
        def initialize(collector)
          @collector = collector
        end

        %i[info warn error].each do |level|
          define_method(level) { |message| @collector.push(JSON.parse(message)) }
        end
      end

      attr_reader :event_logger

      def initialize
        @events = []
        @lock = Mutex.new
        @event_logger = EventLogger.new(logger: Sink.new(self))
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

require "stringio"
require "logger"

module JobSearch
  # EventLogger real gravando em memória, para inspecionar os eventos
  # estruturados que um fluxo produziu.
  class CapturedEvents
    attr_reader :event_logger

    def initialize
      @io = StringIO.new
      logger = Logger.new(@io)
      logger.formatter = ->(_severity, _time, _progname, message) { "#{message}\n" }
      @event_logger = Observability::EventLogger.new(logger: logger)
    end

    def all
      @io.string.lines.map { |line| JSON.parse(line) }
    end

    def spans
      all.select { |event| event["event"] == "span" }
    end

    def raw
      @io.string
    end
  end
end

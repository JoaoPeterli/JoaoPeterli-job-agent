
module JobSearch
  module Observability
    class EventLogger
      FILTERED_VALUE = SensitiveDataFilter::FILTERED_VALUE
      SENSITIVE_KEYS = SensitiveDataFilter::SENSITIVE_KEYS

      def initialize(logger: Rails.logger)
        @logger = logger
      end

      def info(event:, **attributes)
        write(:info, event: event, attributes: attributes)
      end

      def warn(event:, **attributes)
        write(:warn, event: event, attributes: attributes)
      end

      def error(event:, **attributes)
        write(:error, event: event, attributes: attributes)
      end

      private

      def write(level, event:, attributes:)
        payload = {
          timestamp: Time.current.iso8601(6),
          event: event
        }.merge(filter_attributes(attributes))

        @logger.public_send(level, JSON.generate(payload))
      end

      def filter_attributes(value)
        SensitiveDataFilter.call(value)
      end
    end
  end
end

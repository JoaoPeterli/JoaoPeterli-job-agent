
module JobSearch
  module Observability
    class EventLogger
      FILTERED_VALUE = "[FILTERED]".freeze

      SENSITIVE_KEYS = %w[
        password
        access_token
        refresh_token
        api_key
        authorization
        client_secret
        secret
        token
      ].freeze

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
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            result[key] =
              if sensitive_key?(key)
                FILTERED_VALUE
              else
                filter_attributes(item)
              end
          end
        when Array
          value.map { |item| filter_attributes(item) }
        else
          value
        end
      end

      def sensitive_key?(key)
        normalized = key.to_s.downcase

        SENSITIVE_KEYS.include?(normalized) ||
          normalized.end_with?(
            "_password",
            "_token",
            "_secret",
            "_api_key"
          )
      end
    end
  end
end

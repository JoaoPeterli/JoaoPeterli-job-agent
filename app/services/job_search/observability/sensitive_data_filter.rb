module JobSearch
  module Observability
    # Troca por "[FILTERED]" os valores de chaves que parecem segredos
    # (senha, token, api_key...), em qualquer nível de Hash/Array.
    # Usado pelos logs estruturados e pela trilha de auditoria.
    module SensitiveDataFilter
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

      SENSITIVE_SUFFIXES = %w[_password _token _secret _api_key].freeze

      module_function

      def call(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            result[key] = sensitive_key?(key) ? FILTERED_VALUE : call(item)
          end
        when Array
          value.map { |item| call(item) }
        else
          value
        end
      end

      def sensitive_key?(key)
        normalized = key.to_s.downcase

        SENSITIVE_KEYS.include?(normalized) || normalized.end_with?(*SENSITIVE_SUFFIXES)
      end
    end
  end
end

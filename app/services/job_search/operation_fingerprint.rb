require "digest"
require "json"

module JobSearch
  class OperationFingerprint
    def self.call(tool:, arguments:)
      payload = {
        tool: tool.to_s,
        arguments: canonicalize(arguments)
      }

      Digest::SHA256.hexdigest(
        JSON.generate(payload)
      )
    end

    def self.canonicalize(value)
      case value
      when Hash
        value
          .transform_keys(&:to_s)
          .sort
          .to_h
          .transform_values { |v| canonicalize(v) }
      when Array
        value.map { |v| canonicalize(v) }
      else
        value
      end
    end

    private_class_method :canonicalize
  end
end

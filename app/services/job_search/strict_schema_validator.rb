module JobSearch
  # Verifica, antes de chamar a API, se um JSON Schema respeita as regras
  # do modo strict de Structured Outputs:
  #
  # - a raiz é um objeto (não pode ser anyOf);
  # - todo objeto declara additionalProperties: false;
  # - toda propriedade de um objeto está em required (campos opcionais
  #   se expressam com tipo nullable, não omitindo do required).
  #
  # Sem isso, um schema incompatível só apareceria em produção, como
  # erro 400 na primeira chamada ao LLM.
  class StrictSchemaValidator
    COMBINATORS = %w[anyOf allOf oneOf].freeze

    def validate!(schema)
      schema = deep_stringify(schema)

      if schema["type"] != "object" || schema.key?("anyOf")
        raise ArgumentError, "Strict schema root must be an object"
      end

      check!(schema, "$")

      true
    end

    private

    def check!(schema, path)
      return unless schema.is_a?(Hash)

      check_object!(schema, path) if schema["type"] == "object"

      schema.fetch("properties", {}).each do |name, child|
        check!(child, "#{path}.#{name}")
      end

      check!(schema["items"], "#{path}[]") if schema.key?("items")

      COMBINATORS.each do |keyword|
        Array(schema[keyword]).each_with_index do |child, index|
          check!(child, "#{path}.#{keyword}[#{index}]")
        end
      end
    end

    def check_object!(schema, path)
      unless schema["additionalProperties"] == false
        raise ArgumentError,
              "Strict schema object at #{path} must set additionalProperties: false"
      end

      properties = schema.fetch("properties", {}).keys.sort
      required = Array(schema["required"]).map(&:to_s).sort

      return if properties == required

      raise ArgumentError,
            "Strict schema object at #{path} must require every property " \
            "(missing: #{(properties - required).join(', ')})"
    end

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array
        value.map { |item| deep_stringify(item) }
      else
        value
      end
    end
  end
end

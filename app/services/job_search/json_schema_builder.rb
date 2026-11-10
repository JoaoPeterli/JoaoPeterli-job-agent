module JobSearch
  class JsonSchemaBuilder
    def build(argument_schema)
      {
        type: "object",
        properties: build_properties(
          argument_schema
        ),
        required: argument_schema.keys.map(
          &:to_s
        ),
        additionalProperties: false
      }
    end

    private

    def build_properties(argument_schema)
      argument_schema.each_with_object({}) do |(name, type), properties|
        properties[name] = schema_for(
          type
        )
      end
    end

    def schema_for(type)
      return {
        type: "string"
      } if type == String

      return {
        type: "array"
      } if type == Array

      return {
        type: "object"
      } if type == Hash

      if type == ObservationReference
        return observation_reference_schema
      end

      if type.is_a?(Array)
        return {
          type: json_type_for_multiple(
            type
          )
        }
      end

      raise ArgumentError,
            "Unsupported schema type: #{type}"
    end

    def observation_reference_schema
      {
        type: "object",

        properties: {
          "$ref": {
            type: "string"
          }
        },

        required: [
          "$ref"
        ],

        additionalProperties: false
      }
    end

    def json_type_for_multiple(types)
      if boolean_types?(
        types
      )
        return "boolean"
      end

      raise ArgumentError,
            "Unsupported schema types: #{types}"
    end

    def boolean_types?(types)
      types.include?(TrueClass) &&
        types.include?(FalseClass)
    end
  end
end

module JobSearch
  class PlanOutputSchema
    def initialize(tool_catalog:)
      @tool_catalog = tool_catalog
    end

    def to_h
      {
        type: "object",

        properties: {
          steps: {
            type: "array",
            items: {
              anyOf: step_schemas
            }
          }
        },

        required: [
          "steps"
        ],

        additionalProperties: false
      }
    end

    private

    def step_schemas
      @tool_catalog.definitions.map do |definition|
        step_schema_for(
          definition
        )
      end
    end

    def step_schema_for(definition)
      {
        type: "object",

        properties: {
          name: {
            type: "string"
          },

          tool: {
            type: "string",
            const: definition.name.to_s
          },

          arguments: definition.json_schema,

          dependencies: {
            type: "array",
            items: {
              type: "string"
            }
          }
        },

        required: [
          "name",
          "tool",
          "arguments",
          "dependencies"
        ],

        additionalProperties: false
      }
    end
  end
end

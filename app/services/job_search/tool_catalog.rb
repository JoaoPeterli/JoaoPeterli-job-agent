module JobSearch
  class ToolCatalog
    attr_reader :definitions

    def initialize(definitions:)
      @definitions = definitions
    end

    def fetch(name)
      definition = definitions.find do |item|
        item.name == name
      end

      return definition if definition

      raise KeyError,
            "Unknown tool definition: #{name}"
    end

    def to_prompt
      definitions.map do |definition|
        format_definition(
          definition
        )
      end.join("\n\n")
    end

    def json_schemas
      definitions.each_with_object({}) do |definition, schemas|
        schemas[definition.name] = definition.json_schema
      end
    end

    private

    def format_definition(definition)
      data = definition.to_h

      <<~TOOL.strip
        Tool: #{data[:name]}
        Description: #{data[:description]}
        Arguments: #{data[:arguments]}
      TOOL
    end
  end
end


module JobSearch
  class ToolDefinition
    attr_reader :name,
                :description,
                :arguments,
                :side_effects,
                :operation_type

    def initialize(
      name:,
      description:,
      arguments: {},
      schema: {},
      planning_schema: nil,
      side_effects: true,
      operation_type: nil,
      json_schema_builder: JsonSchemaBuilder.new
    )
      @name = name
      @description = description
      @arguments = arguments
      @argument_schema = schema
      @planning_schema = planning_schema
      @json_schema_builder = json_schema_builder
      @side_effects = side_effects

      if operation_type && !side_effects
        raise ArgumentError,
              "Read-only tools cannot have an operation_type"
      end

      @operation_type = operation_type&.to_s
    end

    def argument_schema
      @argument_schema
    end

    def planning_schema
      @planning_schema || argument_schema
    end

    def json_schema
      @json_schema_builder.build(
        planning_schema
      )
    end

    def to_h
      {
        name: name,
        description: description,
        arguments: arguments
      }
    end
  end
end

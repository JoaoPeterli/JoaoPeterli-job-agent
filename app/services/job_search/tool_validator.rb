module JobSearch
  class ToolValidator
    def validate!(arguments:, schema:)
      validate_required_arguments!(
        arguments,
        schema
      )

      validate_unknown_arguments!(
        arguments,
        schema
      )

      validate_types!(
        arguments,
        schema
      )

      true
    end

    private

    def validate_required_arguments!(arguments, schema)
      schema.each_key do |name|
        next if arguments.key?(name)

        raise ArgumentError,
              "Missing argument: #{name}"
      end
    end

    def validate_unknown_arguments!(arguments, schema)
      arguments.each_key do |name|
        next if schema.key?(name)

        raise ArgumentError,
              "Unknown argument: #{name}"
      end
    end

    def validate_types!(arguments, schema)
      schema.each do |name, expected_types|
        value = arguments[name]

        types = Array(
          expected_types
        )

        valid = types.any? do |type|
          value.is_a?(type)
        end

        next if valid

        raise ArgumentError,
              "Invalid type for argument: #{name}"
      end
    end
  end
end

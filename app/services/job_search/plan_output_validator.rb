
module JobSearch
  class PlanOutputValidator
    REQUIRED_STEP_KEYS = [
      :name,
      :tool,
      :arguments,
      :dependencies
    ].freeze

    def validate!(data)
      validate_root!(data)
      validate_steps!(data)

      true
    end

    private

    def validate_root!(data)
      unless data.is_a?(Hash)
        raise PlanValidationError,
              "Plan output must be an object"
      end

      unless data.key?(:steps)
        raise PlanValidationError,
              "Plan output must contain steps"
      end
    end

    def validate_steps!(data)
      steps = data[:steps]

      unless steps.is_a?(Array)
        raise PlanValidationError,
              "Steps must be an array"
      end

      steps.each do |step|
        validate_step!(step)
      end
    end

    def validate_step!(step)
      unless step.is_a?(Hash)
        raise PlanValidationError,
              "Invalid step structure"
      end

      valid = REQUIRED_STEP_KEYS.all? do |key|
        step.key?(key)
      end

      unless valid
        raise PlanValidationError,
              "Invalid step structure"
      end

      validate_step_types!(step)
    end

    def validate_step_types!(step)
      validate_field_type!(step, :name, String)
      validate_field_type!(step, :tool, String)
      validate_field_type!(step, :arguments, Hash)
      validate_field_type!(step, :dependencies, Array)

      validate_step_values!(step)
    end

    def validate_field_type!(step, field, type)
      return if step[field].is_a?(type)

      raise PlanValidationError,
            "Invalid #{field}: expected #{type}"
    end

    def validate_step_values!(step)
      if step[:name].strip.empty?
        raise PlanValidationError,
              "Invalid name: cannot be blank"
      end

      if step[:tool].strip.empty?
        raise PlanValidationError,
              "Invalid tool: cannot be blank"
      end

      step[:dependencies].each do |dependency|
        next if dependency.is_a?(String) &&
                !dependency.strip.empty?

        raise PlanValidationError,
              "Invalid dependency: expected non-empty String"
      end
    end
  end
end

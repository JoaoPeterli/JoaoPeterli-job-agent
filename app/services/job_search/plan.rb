module JobSearch
  class Plan
    attr_reader :steps

    # inputs: nomes de dados recebidos de outros agentes. Um passo pode
    # referenciá-los ({"$ref": "jobs"}) sem dependência: já existem antes
    # de o plano começar.
    def initialize(steps:, inputs: [])
      @steps = steps
      @inputs = inputs.map(&:to_sym)

      validate_unique_names!
      validate_input_names!
      validate_dependencies!
      validate_cycles!
      validate_observation_references!
    end

    def ready_steps(completed_steps:)
      steps.select do |step|
        !completed_steps.include?(step.name) &&
          step.ready?(completed_steps)
      end
    end

    private

    def validate_unique_names!
      names = steps.map(&:name)

      duplicate = names.find do |name|
        names.count(name) > 1
      end

      return unless duplicate

      raise ArgumentError,
            "Duplicated step: #{duplicate}"
    end

    def validate_input_names!
      conflict = steps.map(&:name).find { |name| @inputs.include?(name) }
      return unless conflict

      raise ArgumentError,
            "Step name conflicts with input: #{conflict}"
    end

    def validate_dependencies!
      names = steps.map(&:name)

      steps.each do |step|
        step.dependencies.each do |dependency|
          next if names.include?(dependency)

          raise ArgumentError,
                "Unknown dependency: #{dependency}"
        end
      end
    end

    def validate_cycles!
      visited = {}
      visiting = {}

      steps.each do |step|
        visit(
          step,
          visited: visited,
          visiting: visiting
        )
      end
    end

    def validate_observation_references!
      names = steps.map(&:name)

      steps.each do |step|
        validate_reference_value!(
          step.action.arguments,
          step: step,
          names: names
        )
      end
    end

    def validate_reference_value!(value, step:, names:)
      case value
      when ObservationReference
        validate_reference!(
          value,
          step: step,
          names: names
        )

      when Hash
        value.each_value do |nested_value|
          validate_reference_value!(
            nested_value,
            step: step,
            names: names
          )
        end

      when Array
        value.each do |nested_value|
          validate_reference_value!(
            nested_value,
            step: step,
            names: names
          )
        end
      end
    end

    def validate_reference!(reference, step:, names:)
      return if @inputs.include?(reference.step_name)

      validate_reference_exists!(
        reference,
        names: names
      )

      validate_reference_dependency!(
        reference,
        step: step
      )
    end

    def validate_reference_exists!(reference, names:)
      return if names.include?(
        reference.step_name
      )

      raise ArgumentError,
            "Unknown observation reference: #{reference.step_name}"
    end

    def validate_reference_dependency!(reference, step:)
      return if step.dependencies.include?(
        reference.step_name
      )

      raise ArgumentError,
            "Missing dependency for observation reference: " \
            "#{step.name} -> #{reference.step_name}"
    end

    def visit(step, visited:, visiting:)
      return if visited[step.name]

      if visiting[step.name]
        raise ArgumentError,
              "Cycle detected"
      end

      visiting[step.name] = true

      step.dependencies.each do |dependency|
        dependency_step = find_step(
          dependency
        )

        visit(
          dependency_step,
          visited: visited,
          visiting: visiting
        )
      end

      visiting.delete(
        step.name
      )

      visited[step.name] = true
    end

    def find_step(name)
      steps.find do |step|
        step.name == name
      end
    end
  end
end


require "json"

module JobSearch
  class LlmPlanner
    DEFAULT_MAX_INPUT_TOKENS = 8_000
    MAX_OBJECTIVE_TOKENS = 500
    MAX_REPAIR_TOKENS = 300
    MAX_HISTORY_TOKENS = 400
    MAX_LESSONS_TOKENS = 300

    def initialize(
      llm_client:,
      registry:,
      tool_catalog: ToolCatalog.new(definitions: []),
      output_validator: PlanOutputValidator.new,
      tool_validator: ToolValidator.new,
      context_window: ContextWindow.new(
        max_input_tokens: DEFAULT_MAX_INPUT_TOKENS
      )
    )
      @llm_client = llm_client
      @context_window = context_window
      @registry = registry
      @tool_catalog = tool_catalog
      @output_validator = output_validator
      @tool_validator = tool_validator
    end

    def plan(context:)
      response = @llm_client.complete(
        prompt: build_prompt(context)
      )

      data = parse_response(response)

      validate_and_build_plan(data)
    end

    private

    def parse_response(response)
      JSON.parse(
        response,
        symbolize_names: true
      )
    rescue JSON::ParserError => error
      raise PlanningError.new(
        "Invalid LLM plan",
        cause: error
      )
    end

    def validate_and_build_plan(data)
      @output_validator.validate!(data)

      steps = data.fetch(:steps).map do |step_data|
        build_step(step_data)
      end

      build_validated_plan(steps)
    rescue PlanValidationError => error
      raise PlanningError.new(
        "Invalid LLM plan",
        cause: error
      )
    end

    def build_validated_plan(steps)
      Plan.new(steps: steps)
    rescue ArgumentError => error
      raise PlanValidationError, error.message
    end

    def build_prompt(context)
      @context_window.build(prompt_sections(context)).text
    end

    def prompt_sections(context)
      [
        PromptSection.new(
          name: :role,
          content: "You are an execution planner."
        ),
        PromptSection.new(
          name: :objective,
          content: "Objective:\n#{context.objective}",
          max_tokens: MAX_OBJECTIVE_TOKENS
        ),
        PromptSection.new(
          name: :lessons,
          content: lessons_instructions(context),
          required: false,
          max_tokens: MAX_LESSONS_TOKENS
        ),
        PromptSection.new(
          name: :history,
          content: history_instructions(context),
          required: false,
          max_tokens: MAX_HISTORY_TOKENS
        ),
        PromptSection.new(
          name: :repair,
          content: repair_instructions(context),
          required: false,
          max_tokens: MAX_REPAIR_TOKENS
        ),
        PromptSection.new(
          name: :tools,
          content: "Available tools:\n#{@tool_catalog.to_prompt}"
        ),
        PromptSection.new(
          name: :rules,
          content: planning_rules
        )
      ]
    end

    def planning_rules
      <<~RULES
        Create an execution plan using only the available tools.

        Return only valid JSON.

        The root JSON object must contain a "steps" array.

        Each step must contain:
        - name
        - tool
        - arguments
        - dependencies

        To reference the result of another step, use:
        {
          "$ref": "step_name"
        }

        Important rules:
        - Use only tools listed above.
        - Do not invent tools.
        - Every referenced step must exist.
        - If a step references another step, it must also depend on that step.
        - Do not create cyclic dependencies.
      RULES
    end

    def lessons_instructions(context)
      return "" if context.lessons.empty?

      lines = context.lessons.map { |lesson| "- #{lesson}" }

      <<~LESSONS
        Plans for similar objectives were rejected in previous runs for these reasons. Avoid them:
        #{lines.join("\n")}
      LESSONS
    end

    def history_instructions(context)
      return "" if context.history.empty?

      lines = context.history.map { |entry| "- #{entry}" }

      <<~HISTORY
        Earlier plans in this run were also rejected. Do not repeat these mistakes:
        #{lines.join("\n")}
      HISTORY
    end

    def repair_instructions(context)
      return "" unless context.previous_error

      <<~REPAIR
        This is planning attempt #{context.attempt}.

        The previous plan was rejected.

        Reason:
        #{planning_error_message(context.previous_error)}

        Create a corrected plan that fixes the previous error.
      REPAIR
    end

    def planning_error_message(error)
      error.cause&.message || error.message
    end

    def build_step(step_data)
      tool = step_data.fetch(:tool).to_sym

      validate_tool!(tool)

      arguments = resolve_references(
        step_data.fetch(:arguments, {})
      )

      validate_tool_arguments!(
        tool: tool,
        arguments: arguments
      )

      action = AgentAction.new(
        tool: tool,
        arguments: arguments
      )

      Step.new(
        name: step_data.fetch(:name).to_sym,
        action: action,
        dependencies: step_data.fetch(
          :dependencies, []
        ).map(&:to_sym)
      )
    end

    def validate_tool_arguments!(tool:, arguments:)
      return if @tool_catalog.definitions.empty?

      definition = @tool_catalog.fetch(tool)

      @tool_validator.validate!(
        arguments: arguments,
        schema: definition.planning_schema
      )
    rescue ArgumentError => error
      raise PlanValidationError, error.message
    end

    def resolve_references(value)
      case value
      when Hash
        if reference?(value)
          build_reference(value)
        else
          value.transform_values do |nested_value|
            resolve_references(nested_value)
          end
        end
      when Array
        value.map do |nested_value|
          resolve_references(nested_value)
        end
      else
        value
      end
    end

    def reference?(value)
      value.key?(:$ref)
    end

    def build_reference(value)
      unless value.keys == [ :$ref ]
        raise PlanValidationError,
              "Invalid observation reference: unexpected fields"
      end

      reference = value.fetch(:$ref)

      unless reference.is_a?(String) && !reference.strip.empty?
        raise PlanValidationError,
              "Invalid observation reference: expected non-empty String"
      end

      ObservationReference.new(step_name: reference.to_sym)
    end

    def validate_tool!(tool)
      return if @registry.registered?(tool)

      raise PlanValidationError,
            "Unknown tool: #{tool}"
    end
  end
end

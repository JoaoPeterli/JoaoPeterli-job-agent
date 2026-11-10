require "securerandom"

module JobSearch
  class AgentState
    attr_reader :objective, :run_id, :status, :actions, :step_states, :memory, :inputs

    # inputs: AgentInput recebidos de outros agentes, por nome.
    def initialize(
      objective:,
      run_id: SecureRandom.uuid,
      memory: ShortTermMemory.new,
      inputs: []
    )
      @objective = objective
      @inputs = inputs.to_h { |input| [ input.name, input ] }.freeze
      @step_tools = {}
      @memory = memory
      @run_id = run_id
      @status = :running
      @actions = []
      @step_states = {}
    end

    def add_action(action)
      @actions << action
    end

    def add_observation(step_name, observation)
      step_state_for(step_name).add_observation(observation)
    end

    def observation_for(step_name)
      step_state_for(step_name).observation
    end

    def input?(name)
      @inputs.key?(name.to_sym)
    end

    def input_value(name)
      @inputs.fetch(name.to_sym).value
    end

    # Observações dos passos que usaram a ferramenta, na ordem de execução.
    def observations_from_tool(tool)
      @step_tools.filter_map do |step_name, step_tool|
        next unless step_tool == tool.to_sym

        observation_for(step_name) if step_status(step_name) == :completed
      end
    end

    def observations
      @step_states.each_with_object({}) do |(name, step_state), result|
        next if step_state.observation.nil?

        result[name] = step_state.observation
      end
    end

    def step_status(step_name)
      step_state_for(step_name).status
    end

    def step_statuses
      @step_states.transform_values(&:status)
    end

    def start_step!(step_name, tool: nil)
      @step_tools[step_name] = tool.to_sym if tool
      step_state_for(step_name).start!
    end

    def complete_step!(step_name)
      step_state_for(step_name).complete!
    end

    def fail_step!(step_name, error: nil)
      step_state_for(step_name).fail!(error: error)
    end

    def error_for(step_name)
      step_state_for(step_name).error
    end

    def step_errors
      @step_states.each_with_object({}) do |(name, step_state), result|
        next if step_state.error.nil?

        result[name] = step_state.error
      end
    end

    def record_attempt(step_name, attempt)
      step_state_for(step_name).record_attempt(attempt)
    end

    def attempts_for(step_name)
      step_state_for(step_name).attempts
    end

    def step_attempts
      @step_states.transform_values(&:attempts)
    end

    def step_state(step_name)
      step_state_for(step_name)
    end

    def complete!
      @status = :completed
    end

    def failed!
      @status = :failed
    end

    private

    def step_state_for(step_name)
      @step_states[step_name] ||= StepState.new
    end
  end
end

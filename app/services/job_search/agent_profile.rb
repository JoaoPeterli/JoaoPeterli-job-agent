module JobSearch
  # Papel de um agente especializado.
  #
  # Cada papel tem só as ferramentas de que precisa (menor privilégio,
  # prompt menor e mais focado) e declara o que entrega ao próximo agente:
  # output_name/output_description descrevem o dado, e output_tool diz de
  # quais passos ele sai (observações de todos os passos com essa
  # ferramenta; listas são concatenadas).
  #
  # description e required_inputs são o "contrato público" do papel: é o
  # que o supervisor (Aula 42) vê para decidir a quem delegar, e o que o
  # validador usa para recusar delegações incompatíveis.
  AgentProfile = Data.define(
    :name, :role, :allowed_tools, :max_calls_per_tool,
    :output_name, :output_description, :output_tool,
    :description, :required_inputs
  ) do
    def initialize(
      name:, role:, allowed_tools:, max_calls_per_tool: {},
      output_name: nil, output_description: nil, output_tool: nil,
      description: nil, required_inputs: []
    )
      super(
        description: description,
        required_inputs: required_inputs.map(&:to_sym).freeze,
        name: name.to_s,
        role: role,
        allowed_tools: allowed_tools.map(&:to_sym).freeze,
        max_calls_per_tool: max_calls_per_tool.transform_keys(&:to_sym).freeze,
        output_name: output_name&.to_sym,
        output_description: output_description,
        output_tool: output_tool&.to_sym
      )
    end

    def to_roster
      lines = [ "- #{name}: #{description}" ]
      lines << "  requires inputs: #{required_inputs.join(', ')}" if required_inputs.any?
      lines << "  produces: #{output_name} (#{output_description})" if output_name
      lines.join("\n")
    end

    def output_from(state)
      return nil unless output_tool

      observations = state.observations_from_tool(output_tool)
      observations.all?(Array) ? observations.flatten(1) : observations.last
    end

    def output_input(state)
      AgentInput.new(name: output_name, description: output_description, value: output_from(state))
    end
  end
end

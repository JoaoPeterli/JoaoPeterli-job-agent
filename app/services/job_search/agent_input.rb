module JobSearch
  # Dado recebido de outro agente (ex.: vagas encontradas pelo pesquisador).
  #
  # O LLM vê só o nome, a descrição e o tamanho (#summary) e referencia o
  # input no plano com {"$ref": "<name>"}. O valor nunca entra no prompt:
  # dados externos (títulos de vagas, por exemplo) podem conter texto
  # malicioso, e o LLM não precisa lê-los para planejar.
  AgentInput = Data.define(:name, :description, :value) do
    def initialize(name:, description:, value:)
      super(name: name.to_sym, description: description.to_s, value: value)
    end

    def summary
      size = value.respond_to?(:size) && !value.is_a?(String) ? " (#{value.size} items)" : ""

      "#{name}: #{description}#{size}"
    end
  end
end

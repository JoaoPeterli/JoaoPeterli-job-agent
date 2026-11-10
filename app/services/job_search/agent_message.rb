require "securerandom"

module JobSearch
  # Mensagem entre agentes (o "protocolo" do time).
  #
  # kind:
  #   :task    -> coordenador pede um trabalho a um agente
  #   :result  -> agente entrega o resultado
  #   :failure -> agente falhou (classe do erro, sem a mensagem)
  #
  # payload carrega só metadados (run_id do agente, status, resumo do
  # output). O dado em si viaja como AgentInput para o próximo agente e
  # nunca é colado no prompt dele.
  AgentMessage = Data.define(:id, :kind, :from, :to, :pipeline_run_id, :payload) do
    # Método, não constante: uma constante dentro deste bloco seria
    # definida em JobSearch (escopo léxico), não em AgentMessage.
    def self.kinds = %i[task result failure].freeze

    def initialize(kind:, from:, to:, pipeline_run_id:, payload: {}, id: SecureRandom.uuid)
      kind = kind.to_sym
      raise ArgumentError, "Unknown message kind: #{kind}" unless self.class.kinds.include?(kind)

      super(id: id, kind: kind, from: from.to_s, to: to.to_s, pipeline_run_id: pipeline_run_id, payload: payload.freeze)
    end

    def to_h
      { id: id, kind: kind.to_s, from: from, to: to, pipeline_run_id: pipeline_run_id, payload: payload }
    end
  end
end

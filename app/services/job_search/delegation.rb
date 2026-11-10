module JobSearch
  # Uma tarefa entregue a um agente especialista.
  #
  # id: nome da tarefa (único no plano), usado para ligar outputs a inputs
  # agent: nome do AgentProfile que executa
  # task: objetivo dado ao especialista
  # inputs: ids de delegações anteriores cujos outputs esta tarefa recebe
  Delegation = Data.define(:id, :agent, :task, :inputs) do
    def initialize(id:, agent:, task:, inputs: [])
      super(id: id.to_s, agent: agent.to_s, task: task.to_s, inputs: inputs.map(&:to_s).freeze)
    end
  end
end

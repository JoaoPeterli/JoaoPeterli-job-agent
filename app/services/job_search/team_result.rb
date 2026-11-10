module JobSearch
  # Resultado de um time de agentes (pipeline fixo ou supervisor).
  #
  # status: :completed ou :stopped_early (alguma delegação foi pulada por
  #         não ter dado para trabalhar)
  # output: AgentInput da última delegação executada
  # outputs: AgentInput por id de delegação
  # agent_run_ids: run_id de cada agente, por id de delegação
  TeamResult = Data.define(:run_id, :status, :output, :outputs, :messages, :agent_run_ids)
end

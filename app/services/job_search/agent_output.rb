module JobSearch
  # Resultado final de um agente único (GENERALIST): a análise, se houve;
  # senão as vagas encontradas. Usado pelo harness e pelos evals.
  module AgentOutput
    module_function

    def from(state)
      state.observations_from_tool(:analyze_jobs).last || state.observations_from_tool(:search_jobs).flatten(1)
    end
  end
end

module JobSearch
  # Resultado final de um agente único (GENERALIST): a análise, se houve;
  # senão as vagas encontradas. Usado pelo harness e pelos evals.
  #
  # Com o laço ReAct há uma análise por iteração: o resultado junta todas,
  # sem repetir vaga (a mesma vaga achada duas vezes fica com a maior nota).
  module AgentOutput
    module_function

    def from(state)
      analyses = state.observations_from_tool(:analyze_jobs)
      return state.observations_from_tool(:search_jobs).flatten(1) if analyses.empty?
      return analyses.first if analyses.one?

      merge(analyses.flatten(1))
    end

    def merge(jobs)
      jobs.group_by { |job| JobListing.key_for(title: job[:title], company: job[:company]) }
          .values.map { |same| same.max_by { |job| job[:score].to_i } }
    end
  end
end

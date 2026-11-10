module JobSearch
  # Papéis disponíveis.
  #
  # GENERALIST é o agente único das aulas anteriores (todas as ferramentas).
  # RESEARCHER e ANALYST dividem o mesmo trabalho em dois especialistas:
  # o pesquisador só busca; o analista não busca, só avalia as vagas que
  # recebe como input.
  module AgentProfiles
    GENERALIST = AgentProfile.new(
      name: "job_search",
      role: LlmPlanner::DEFAULT_ROLE,
      allowed_tools: %i[search_jobs candidate_profile analyze_jobs],
      max_calls_per_tool: { search_jobs: 5 }
    )

    RESEARCHER = AgentProfile.new(
      name: "researcher",
      role: "You are the research agent of a job search team. " \
            "Your only job is to search for job openings that match the objective. " \
            "Do not analyze or rank jobs: another agent does that.",
      allowed_tools: %i[search_jobs],
      max_calls_per_tool: { search_jobs: 3 },
      output_name: :jobs,
      output_description: "job openings found by the research agent",
      output_tool: :search_jobs
    )

    ANALYST = AgentProfile.new(
      name: "analyst",
      role: "You are the analysis agent of a job search team. " \
            "Jobs were already found by another agent and are given to you as an input. " \
            "Load the candidate profile and analyze the given jobs against it. Do not search for jobs.",
      allowed_tools: %i[candidate_profile analyze_jobs],
      max_calls_per_tool: { analyze_jobs: 1 },
      output_name: :ranked_jobs,
      output_description: "jobs scored against the candidate profile",
      output_tool: :analyze_jobs
    )

    ALL = [ GENERALIST, RESEARCHER, ANALYST ].to_h { |profile| [ profile.name, profile ] }.freeze

    def self.fetch(name)
      ALL.fetch(name.to_s) { raise KeyError, "Unknown agent profile: #{name}" }
    end
  end
end

module JobSearch
  # O que o agente "observa" ao fim de uma iteração do laço ReAct: as buscas
  # que fez e o que encontrou, resumido. O Reflector decide só com isto
  # (contagens e os títulos das melhores vagas), nunca com a lista inteira.
  class IterationObservation
    STRONG_SCORE = 70
    TOP = 5

    attr_reader :iteration, :searches, :jobs_found, :strong_matches, :top_jobs

    def initialize(iteration:, searches:, jobs_found:, strong_matches:, top_jobs:)
      @iteration = iteration
      @searches = searches
      @jobs_found = jobs_found
      @strong_matches = strong_matches
      @top_jobs = top_jobs
    end

    # plan: o plano desta iteração (só os passos dela, não os das anteriores).
    def self.build(iteration:, plan:, state:)
      search_steps = plan.steps.select { |step| step.action.tool == :search_jobs }
      analyze_step = plan.steps.reverse.find { |step| step.action.tool == :analyze_jobs }

      found = search_steps.flat_map { |step| Array(state.observation_for(step.name)) }
      analyzed = analyze_step ? Array(state.observation_for(analyze_step.name)) : found
      ranked = analyzed.select { |job| job.is_a?(Hash) }.sort_by { |job| -job[:score].to_i }

      new(
        iteration: iteration,
        searches: search_steps.map { |step| step.action.arguments.slice(:technology, :remote) },
        jobs_found: found.size,
        strong_matches: ranked.count { |job| job[:score].to_i >= STRONG_SCORE },
        top_jobs: ranked.first(TOP).map { |job| { title: job[:title].to_s, score: job[:score] } }
      )
    end

    def summary
      tried = searches.map { |search| "\"#{search[:technology]}\"#{' (remote)' if search[:remote]}" }.join(", ")
      "Iteration #{iteration}: searched #{tried.presence || 'nothing'}; #{jobs_found} jobs found, " \
        "#{strong_matches} strong matches (score >= #{STRONG_SCORE})."
    end

    # Formato salvo no resultado do run (tela "Raciocínio do agente").
    def to_h
      { iteration: iteration, searches: searches, jobs_found: jobs_found, strong_matches: strong_matches }
    end
  end
end

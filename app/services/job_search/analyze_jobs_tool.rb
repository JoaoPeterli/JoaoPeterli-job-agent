require "timeout"

module JobSearch
  # Nota de aderência (0-100) de cada vaga ao perfil do candidato:
  #
  #   skills       20 por skill do perfil no título ou nas tags (máx. 60)
  #   senioridade  20 se o título pede o nível do perfil; 10 se não cita
  #                nível nenhum; 0 se pede outro nível
  #   modalidade   20 se a vaga é remota e o perfil quer remoto; perfil que
  #                aceita presencial também ganha 20 com vaga na sua cidade
  #
  # Com um evaluator (LLM), as melhores vagas pela régua acima são
  # reavaliadas pelo LLM, que dá a nota final e o motivo (score_reason).
  # Se o LLM falhar, fica a nota da régua: o run nunca cai por isso.
  class AnalyzeJobsTool
    SKILL_POINTS = 20
    MAX_SKILL_POINTS = 60
    SENIORITY_POINTS = 20
    UNSTATED_SENIORITY_POINTS = 10
    WORKPLACE_POINTS = 20
    # Abaixo do timeout da ferramenta (15 s, Container): se o LLM demorar,
    # vale a régua, em vez de o timeout da ferramenta derrubar o run.
    EVALUATION_TIMEOUT_SECONDS = 10
    # Indexar as vagas (embeddings, RAG) é um extra: prazo curto e, se
    # falhar, a análise segue sem índice.
    INDEXING_TIMEOUT_SECONDS = 4

    SENIORITY_PATTERNS = {
      "junior" => /\b(j[uú]nior|jr\.?|entry[- ]level|trainee|est[aá]gi[oá]ri[oa]?)(?![[:alnum:]])/i,
      "pleno" => /\b(pleno|mid[- ]?level|intermediate)\b/i,
      "senior" => /\b(s[eê]nior|sr\.?)(?![[:alnum:]])/i,
      "especialista" => /\b(staff|principal|especialista|specialist|tech lead|lead)\b/i
    }.freeze

    def initialize(evaluator: nil, indexer: nil, event_logger: Observability::EventLogger.new,
                   evaluation_timeout: EVALUATION_TIMEOUT_SECONDS)
      @evaluator = evaluator
      @indexer = indexer
      @event_logger = event_logger
      @evaluation_timeout = evaluation_timeout
    end

    def call(jobs:, profile:)
      index(jobs)
      normalized = normalize(profile)

      scored = jobs.map do |job|
        job.merge(score: skill_points(job, normalized) + seniority_points(job, normalized) +
                         workplace_points(job, normalized))
      end

      @evaluator ? evaluate_with_llm(scored, profile) : scored
    end

    private

    # Grava as vagas no índice vetorial (busca semântica e "parecidas").
    def index(jobs)
      return unless @indexer

      Timeout.timeout(INDEXING_TIMEOUT_SECONDS, EmbeddingError, "indexing timed out") { @indexer.index(jobs) }
    rescue EmbeddingError, ActiveRecord::ActiveRecordError => error
      @event_logger.warn(event: "job_index.failed", error_class: error.class.name, error: error.message.truncate(200))
    end

    # Só as melhores pela régua vão ao LLM (custo previsível); a ordem
    # original das vagas é mantida.
    def evaluate_with_llm(scored, profile)
      top = scored.each_with_index.sort_by { |job, index| [ -job[:score], index ] }.first(@evaluator.max_jobs).map(&:last)
      evaluations = Timeout.timeout(@evaluation_timeout, JobEvaluationError, "LLM evaluation timed out") do
        @evaluator.evaluate(jobs: top.map { |index| scored[index] }, profile: profile)
      end

      scored.each_with_index.map do |job, index|
        evaluation = (position = top.index(index)) && evaluations[position]
        next job.merge(scored_by: "rules") unless evaluation

        job.merge(score: evaluation.score, score_reason: evaluation.reason, rule_score: job[:score], scored_by: "llm")
      end
    rescue JobEvaluationError, PlanningError => error # PlanningError: falhas do LLM e orçamento estourado
      @event_logger.warn(event: "job_evaluation.failed", error_class: error.class.name, error: error.message.truncate(200))
      scored.map { |job| job.merge(scored_by: "rules") }
    end

    def normalize(profile)
      profile = profile.to_h.transform_keys(&:to_sym)
      profile.merge(skills: Array(profile[:skills]), seniority: profile[:seniority].to_s.downcase.tr("ê", "e"))
    end

    def skill_points(job, profile)
      text = ([ job[:title] ] + Array(job[:tags])).compact.join(" | ")
      matches = profile[:skills].count do |skill|
        text.match?(/(?<![[:alnum:]])#{Regexp.escape(skill)}(?![[:alnum:]])/i)
      end

      [ matches * SKILL_POINTS, MAX_SKILL_POINTS ].min
    end

    def seniority_points(job, profile)
      levels = SENIORITY_PATTERNS.select { |_, pattern| job[:title].to_s.match?(pattern) }.keys
      return UNSTATED_SENIORITY_POINTS if levels.empty?

      levels.include?(profile[:seniority]) ? SENIORITY_POINTS : 0
    end

    def workplace_points(job, profile)
      return WORKPLACE_POINTS if job[:remote] && profile[:remote]
      return 0 if profile[:remote]

      near = profile[:location].present? && job[:location].to_s.downcase.include?(profile[:location].to_s.downcase)
      job[:remote] || near ? WORKPLACE_POINTS : 0
    end
  end
end

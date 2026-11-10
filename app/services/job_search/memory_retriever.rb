module JobSearch
  # Recupera lições de execuções anteriores para um novo objetivo.
  #
  # Relevância = similaridade de Jaccard entre os termos do objetivo
  # atual e os do objetivo do run antigo. É simples, determinística e
  # não depende de serviço externo. Pode ser trocada por busca vetorial
  # (embeddings + pgvector) sem mudar quem usa lessons_for.
  #
  # Hoje as lições são os motivos de planos rejeitados: são curtas,
  # geradas pelos nossos validadores e dizem exatamente o que evitar.
  class MemoryRetriever
    LESSON_KINDS = [ :plan_rejected ].freeze
    ATTEMPT_PREFIX = /\AAttempt \d+: /

    STOPWORDS = %w[
      a o as os de da do das dos e em para por com um uma que no na nos nas
      the an and or of to in on for with at by from is are be
      vaga vagas job jobs encontrar find buscar search
    ].freeze

    def initialize(
      store:,
      max_lessons: 5,
      candidate_limit: 200,
      min_similarity: 0.2,
      lesson_policy: LessonPolicy.new,
      event_logger: Observability::EventLogger.new
    )
      @store = store
      @lesson_policy = lesson_policy
      @event_logger = event_logger
      @max_lessons = max_lessons
      @candidate_limit = candidate_limit
      @min_similarity = min_similarity
    end

    def lessons_for(objective:, exclude_run_id: nil)
      objective_terms = terms(objective)
      return [] if objective_terms.empty?

      candidates = @store.candidates(
        kinds: LESSON_KINDS,
        limit: @candidate_limit,
        exclude_run_id: exclude_run_id
      )

      candidates
        .map { |record| [ similarity(objective_terms, terms(record.objective)), record ] }
        .select { |score, _record| score >= @min_similarity }
        .sort_by { |score, record| [ -score, -record.created_at.to_f ] }
        .map { |_score, record| [ record, record.content.sub(ATTEMPT_PREFIX, "") ] }
        .select { |record, lesson| allowed_lesson?(record, lesson) }
        .map(&:last)
        .uniq
        .first(@max_lessons)
    end

    private

    # Lições fora da allowlist nunca voltam ao prompt (injeção armazenada).
    def allowed_lesson?(record, lesson)
      return true if @lesson_policy.allowed?(lesson)

      @event_logger.warn(
        event: "agent_memory.lesson_rejected",
        run_id: record.run_id,
        memory_entry_id: record.id
      )

      false
    end

    def terms(text)
      text.to_s
        .unicode_normalize(:nfkd)
        .gsub(/\p{Mn}/, "")
        .downcase
        .scan(/[a-z0-9.+#]+/)
        .map { |term| term.delete_suffix(".") }
        .reject { |term| term.length < 2 || STOPWORDS.include?(term) }
        .to_set
    end

    def similarity(left, right)
      return 0.0 if left.empty? || right.empty?

      (left & right).size.fdiv((left | right).size)
    end
  end
end

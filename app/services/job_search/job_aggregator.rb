module JobSearch
  # Busca em todas as fontes em paralelo e devolve as vagas que combinam com
  # a tecnologia (e com "remoto", se pedido), sem duplicadas, mais recentes
  # primeiro. Uma fonte fora do ar não derruba a busca: vira um aviso no
  # log. Só quando TODAS falham a busca falha (erro transitório).
  class JobAggregator
    # Até 10 vagas por fonte x 11 fontes. O LLM nunca vê os valores (só a
    # referência), então mais vagas não custam tokens.
    DEFAULT_LIMIT = 100
    # Issues do GitHub e alguns feeds mantêm anúncios antigos: vaga com mais
    # de MAX_AGE provavelmente já foi preenchida. Sem data, a vaga fica.
    MAX_AGE = 60.days
    # Nenhuma fonte ocupa a lista sozinha (fontes grandes publicam muito).
    MAX_PER_SOURCE = 10
    STOPWORDS = %w[on de da do e and the with com em para for developer dev desenvolvedor].freeze

    def initialize(sources:, runner: ParallelRunner.new(max_parallel: 6),
                   event_logger: Observability::EventLogger.new, limit: DEFAULT_LIMIT)
      @sources = sources
      @runner = runner
      @event_logger = event_logger
      @limit = limit
    end

    def search(technology:, remote:)
      matcher = matcher_for(technology)
      outcomes = @runner.map(@sources) { |source| listings_from(source, technology: technology, remote: remote) }
      report_failures(outcomes)

      outcomes.select(&:ok?).flat_map(&:value)
        .select { |job| matcher.call(job) && (!remote || job.remote) && fresh?(job) }
        .uniq(&:dedup_key)
        .sort_by { |job| -(job.published_at&.to_i || 0) }
        .group_by(&:source).flat_map { |_, jobs| jobs.first(MAX_PER_SOURCE) }
        .sort_by { |job| -(job.published_at&.to_i || 0) }
        .first(@limit)
    end

    private

    def fresh?(job)
      job.published_at.nil? || job.published_at >= MAX_AGE.ago
    end

    def listings_from(source, technology:, remote:)
      source.respond_to?(:search) ? source.search(technology: technology, remote: remote) : source.fetch
    end

    # Casa a expressão inteira ou qualquer termo relevante dela, como palavra
    # inteira: "Java" não casa com "JavaScript"; "Ruby on Rails" casa com
    # vagas de Ruby ou de Rails.
    def matcher_for(technology)
      phrase = technology.to_s.downcase.strip
      terms = phrase.split(/[\s,\/]+/).reject { |term| term.length < 2 || STOPWORDS.include?(term) }
      patterns = ([ phrase ] + terms).uniq.reject(&:empty?).map { |term| /(?<![[:alnum:]])#{Regexp.escape(term)}(?![[:alnum:]])/i }

      lambda do |job|
        haystack = ([ job.title ] + job.tags).compact.join(" | ")
        patterns.any? { |pattern| haystack.match?(pattern) }
      end
    end

    def report_failures(outcomes)
      failures = outcomes.each_with_index.reject { |outcome, _| outcome.ok? }

      failures.each do |outcome, index|
        @event_logger.warn(event: "job_source.failed", source: source_name(@sources[index]),
                           error_class: outcome.error.class.name, error: outcome.error.message.truncate(200))
      end

      return unless failures.size == outcomes.size && outcomes.any?

      raise JobSourcesUnavailableError, "All job sources failed (#{failures.size})"
    end

    def source_name(source)
      source.class.const_defined?(:NAME) ? source.class::NAME : source.class.name
    end
  end
end

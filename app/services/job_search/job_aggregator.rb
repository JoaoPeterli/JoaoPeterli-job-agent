module JobSearch
  # Busca em todas as fontes em paralelo e devolve as vagas que combinam com
  # a tecnologia (e com "remoto", se pedido), sem duplicadas, mais recentes
  # primeiro. Uma fonte fora do ar não derruba a busca: vira um aviso no
  # log. Só quando TODAS falham a busca falha (erro transitório).
  class JobAggregator
    DEFAULT_LIMIT = 25
    # Issues do GitHub e alguns feeds mantêm anúncios antigos: vaga com mais
    # de MAX_AGE provavelmente já foi preenchida. Sem data, a vaga fica.
    MAX_AGE = 60.days
    STOPWORDS = %w[on de da do e and the with com em para for developer dev desenvolvedor].freeze

    def initialize(sources:, runner: ParallelRunner.new(max_parallel: 4),
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

module JobSearch
  # Índice vetorial das vagas (pgvector): grava as vagas vistas com o
  # embedding do texto, acha as "parecidas" e faz busca semântica (pelo
  # significado, não pelas palavras exatas). Só gera embedding do que ainda
  # não tem: rever a mesma vaga não custa nada.
  class JobIndex
    def self.default
      new(embedder: EmbeddingClient.new)
    end

    def initialize(embedder:, clock: -> { Time.current })
      @embedder = embedder
      @clock = clock
    end

    # jobs: hashes (saída da search_jobs). Devolve { job_key => JobPosting }.
    def index(jobs, run_id: nil)
      jobs = jobs.map { |job| job.to_h.stringify_keys }.select { |job| job["title"].present? }
      by_key = jobs.index_by { |job| JobFeedback.key_for(job) }
      return {} if by_key.empty?

      existing = JobPosting.where(job_key: by_key.keys).index_by(&:job_key)
      postings = by_key.map { |key, job| assign(existing[key] || JobPosting.new(job_key: key, first_seen_run_id: run_id), job) }

      missing = postings.select { |posting| posting.embedding.nil? }
      @embedder.embed(missing.map { |posting| JobText.for(posting.to_job) })
               .each_with_index { |vector, i| missing[i].embedding = vector }

      JobPosting.transaction { postings.each(&:save!) }
      postings.index_by(&:job_key)
    end

    def similar(posting, limit: 10)
      return [] unless posting&.embedding

      posting.nearest_neighbors(:embedding, distance: "cosine").first(limit)
    end

    # Busca híbrida: o vetor traz os candidatos pelo significado e os termos
    # da busca dão um bônus a quem os contém no título ou nas tags. Só o
    # vetor favorece textos no mesmo idioma da busca ("backend com LLM" puxava
    # vagas em português sem IA) e dilui siglas técnicas como LLM e RAG.
    CANDIDATES = 50
    KEYWORD_WEIGHT = 0.2
    STOPWORDS = %w[com de da do das dos e em para por que uma um the and with for of in to vaga vagas job jobs].freeze

    def search(query, limit: 20)
      vector = @embedder.embed([ query ]).first
      candidates = JobPosting.embedded.nearest_neighbors(:embedding, vector, distance: "cosine").first(CANDIDATES)
      terms = query.downcase.scan(/[[:alnum:]][[:alnum:].+#-]*/).reject { |term| term.length < 2 || STOPWORDS.include?(term) }.uniq

      candidates.sort_by { |posting| -hybrid_score(posting, terms) }.first(limit)
    end

    # Vetor da marcação 👍/👎: o da vaga, se já indexada (sem custo); senão, gera.
    def embed_feedback(feedback)
      vector = JobPosting.find_by(job_key: feedback.job_key)&.embedding ||
               @embedder.embed([ JobText.for(feedback.to_memory) ]).first
      feedback.update!(embedding: vector)
    end

    private

    # Similaridade (1 - distância) + bônus pela fração de termos encontrados.
    # Também grava o score em neighbor_distance, para a tela mostrar a nota final.
    def hybrid_score(posting, terms)
      similarity = 1 - posting.neighbor_distance
      return similarity if terms.empty?

      text = ([ posting.title ] + posting.tags).join(" ").downcase
      found = terms.count { |term| text.match?(/(?<![[:alnum:]])#{Regexp.escape(term)}(?![[:alnum:]])/) }
      score = similarity + (KEYWORD_WEIGHT * found / terms.size)
      posting.neighbor_distance = 1 - score
      score
    end

    def assign(posting, job)
      posting.assign_attributes(
        title: job["title"].to_s.truncate(200), company: job["company"], location: job["location"],
        source: job["source"], url: JobListing.safe_url(job["url"]), remote: job["remote"] == true,
        tags: Array(job["tags"]).first(10), last_seen_at: @clock.call,
        published_at: (Time.zone.parse(job["published_at"].to_s) if job["published_at"].present?)
      )
      posting
    rescue ArgumentError
      posting.published_at = nil
      posting
    end
  end
end

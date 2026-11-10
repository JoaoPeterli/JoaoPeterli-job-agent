module JobSearch
  # O "R" do RAG da avaliação: em vez das 10 marcações mais recentes, busca
  # (por similaridade de embedding) as marcações 👍/👎 mais parecidas com as
  # vagas que estão sendo avaliadas. Lembra de tudo o que o usuário marcou,
  # mas manda ao LLM só o que importa para estas vagas.
  #
  # Sem marcações com embedding (RAG recém-ligado), cai na memória recente.
  class PreferenceMemory
    NEIGHBORS_PER_JOB = 3
    # Distância de cosseno máxima (0 = idêntico, 2 = oposto): acima disso a
    # marcação não diz nada sobre a vaga e só gastaria tokens.
    MAX_DISTANCE = 0.55

    def initialize(index:)
      @index = index
    end

    def relevant_for(jobs)
      return JobFeedback.preferences unless JobFeedback.where.not(embedding: nil).exists?

      postings = @index.index(jobs)
      vectors = postings.values.filter_map(&:embedding)

      {
        liked: nearest(vectors, "like"),
        disliked: nearest(vectors, "dislike")
      }
    end

    private

    # Para cada vaga, as marcações mais próximas; junta, ordena pela menor
    # distância e corta no limite da memória.
    def nearest(vectors, verdict)
      candidates = vectors.flat_map do |vector|
        JobFeedback.where(verdict: verdict).where.not(embedding: nil)
                   .nearest_neighbors(:embedding, vector, distance: "cosine")
                   .first(NEIGHBORS_PER_JOB)
                   .select { |feedback| feedback.neighbor_distance <= MAX_DISTANCE }
      end

      candidates.group_by(&:id).values.map { |same| same.min_by(&:neighbor_distance) }
                .sort_by(&:neighbor_distance).first(JobFeedback::MAX_IN_MEMORY).map(&:to_memory)
    end
  end
end

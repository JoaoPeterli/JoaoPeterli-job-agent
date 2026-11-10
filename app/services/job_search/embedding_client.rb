module JobSearch
  # Embeddings da OpenAI (text-embedding-3-small, 1536 dimensões): texto ->
  # vetor, para comparar vagas por significado (pgvector, distância de
  # cosseno). Em lote: uma chamada para até MAX_BATCH textos.
  class EmbeddingClient
    MODEL = "text-embedding-3-small".freeze
    DIMENSIONS = 1536
    MAX_BATCH = 100
    MAX_INPUT_CHARS = 2_000

    def initialize(client: nil, model: MODEL, event_logger: Observability::EventLogger.new)
      @client = client
      @model = model
      @event_logger = event_logger
    end

    # Devolve um vetor por texto, na mesma ordem.
    def embed(texts)
      texts = Array(texts).map { |text| text.to_s.strip.first(MAX_INPUT_CHARS).presence || "-" }
      return [] if texts.empty?

      texts.each_slice(MAX_BATCH).flat_map { |batch| request(batch) }
    end

    private

    def request(batch)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = client.embeddings.create(model: @model, input: batch)
      vectors = response.data.sort_by(&:index).map(&:embedding)
      raise EmbeddingError, "expected #{batch.size} embeddings, got #{vectors.size}" unless vectors.size == batch.size

      @event_logger.info(event: "embedding.call", model: @model, inputs: batch.size,
                         total_tokens: response.usage&.total_tokens,
                         duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
      vectors
    rescue OpenAI::Errors::Error => error
      raise EmbeddingError, "embedding provider failed (#{error.class.name.demodulize})"
    end

    def client
      @client ||= OpenAI::Client.new
    end
  end
end

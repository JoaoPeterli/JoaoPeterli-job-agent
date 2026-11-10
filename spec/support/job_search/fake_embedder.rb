require "zlib"

module JobSearch
  # Embedder falso e determinístico para specs com pgvector de verdade:
  # cada palavra liga uma dimensão (saco de palavras), então textos com
  # palavras em comum ficam próximos pela distância de cosseno.
  class FakeEmbedder
    attr_reader :calls

    def initialize = @calls = []

    def embed(texts)
      texts = Array(texts)
      @calls << texts
      texts.map { |text| vector(text) }
    end

    def vector(text)
      values = Array.new(EmbeddingClient::DIMENSIONS, 0.0)
      text.to_s.downcase.scan(/[[:alnum:]]+/).each { |word| values[Zlib.crc32(word) % values.size] += 1.0 }
      values[0] += 0.01 if values.all?(&:zero?) # vetor nulo não tem cosseno
      values
    end
  end
end

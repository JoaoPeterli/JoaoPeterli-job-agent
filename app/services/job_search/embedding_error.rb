module JobSearch
  # Falha ao gerar embeddings (provedor fora, resposta inesperada). Quem
  # usa RAG cai no comportamento sem RAG: busca semântica é um extra.
  class EmbeddingError < StandardError
  end
end

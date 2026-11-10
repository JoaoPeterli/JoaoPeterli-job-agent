module JobSearch
  # A mesma chave de idempotência chegou com outro pedido (objetivo ou
  # modo diferentes). Subclasse de ArgumentError por compatibilidade.
  class IdempotencyKeyConflict < ArgumentError
  end
end

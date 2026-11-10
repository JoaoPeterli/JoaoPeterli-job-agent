module JobSearch
  # Falha transitória (ex.: provedor de LLM fora do ar): o run voltou para
  # a fila e o job deve tentar de novo mais tarde. O erro original fica em
  # #cause.
  class RunRetryable < StandardError; end
end

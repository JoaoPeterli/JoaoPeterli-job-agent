module JobSearch
  # Levantado quando um recurso externo rejeita uma escrita porque
  # já aceitou um fencing token maior para a mesma chave. Indica que
  # o worker atual é obsoleto e que a escrita não teve efeito.
  class StaleFencingTokenError < PermanentError
  end
end

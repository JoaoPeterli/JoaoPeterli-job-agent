module JobSearch
  # A avaliação por LLM falhou (resposta inválida). Quem chama volta para
  # a nota por regras: a avaliação melhora o ranking, mas não é essencial.
  class JobEvaluationError < StandardError
  end
end

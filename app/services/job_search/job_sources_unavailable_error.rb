module JobSearch
  # Todas as fontes falharam: transitório, a busca pode ser tentada de novo.
  class JobSourcesUnavailableError < TransientError
  end
end

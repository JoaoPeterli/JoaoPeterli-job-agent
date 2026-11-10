module JobSearch
  # Uma fonte de vagas falhou (rede, HTTP, formato). O agregador registra
  # e segue com as outras fontes.
  class JobSourceError < StandardError
  end
end

module JobSearch
  # Busca vagas reais nas fontes configuradas (ver JobSources). A ferramenta
  # não tem efeitos colaterais: só lê feeds públicos.
  class SearchJobsTool
    def initialize(aggregator: JobAggregator.new(sources: JobSources.configured))
      @aggregator = aggregator
    end

    def call(technology:, remote:)
      @aggregator.search(technology: technology, remote: remote).map(&:to_tool_output)
    end
  end
end

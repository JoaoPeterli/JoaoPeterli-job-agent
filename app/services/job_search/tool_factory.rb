module JobSearch
  # O Executor cria cada ferramenta com `registry.fetch(nome).new`. Para
  # ferramentas com dependências (ex.: o LLM avaliador), registra-se uma
  # fábrica que responde a `new` e monta a ferramenta na hora da execução.
  class ToolFactory
    def initialize(&builder)
      @builder = builder
    end

    def new
      @builder.call
    end
  end
end

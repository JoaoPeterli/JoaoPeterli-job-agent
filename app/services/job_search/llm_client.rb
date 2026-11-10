module JobSearch
  # Interface de um LLM.
  #
  # generate: chamada crua, devolve LlmResponse (texto, status, uso de tokens).
  # complete: devolve só o texto, já validado pelo LlmResponseContract.
  class LlmClient
    def generate(prompt:)
      raise NotImplementedError,
            "Subclasses must implement #generate"
    end

    def complete(prompt:)
      LlmResponseContract.new.text!(generate(prompt: prompt))
    end
  end
end

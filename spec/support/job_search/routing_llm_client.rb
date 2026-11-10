module JobSearch
  # LLM de teste para agentes em paralelo: a resposta é escolhida pelo
  # conteúdo do prompt (primeira rota cujo texto aparece nele), e não pela
  # ordem das chamadas, que deixa de ser determinística com threads.
  #
  # routes: { "trecho do prompt" => [respostas em ordem] }
  class RoutingLlmClient < LlmClient
    class NoRoute < StandardError; end

    def initialize(routes, response_contract: LlmResponseContract.new)
      @routes = routes.transform_values(&:dup)
      @response_contract = response_contract
      @prompts = []
      @lock = Mutex.new
    end

    def generate(prompt:)
      response = @lock.synchronize do
        @prompts << prompt
        key, responses = @routes.find { |fragment, _| prompt.include?(fragment) }
        raise NoRoute, "No route matches prompt #{@prompts.size}" unless key
        raise NoRoute, "Route #{key.inspect} has no responses left" if responses.empty?

        responses.shift
      end

      case response
      when Exception then raise response
      when LlmResponse then response
      else LlmResponse.new(text: response)
      end
    end

    def complete(prompt:)
      @response_contract.text!(generate(prompt: prompt))
    end

    def prompts
      @lock.synchronize { @prompts.dup }
    end

    def calls
      prompts.size
    end
  end
end

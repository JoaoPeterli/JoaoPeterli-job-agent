module JobSearch
  # LLM roteirizado para testes de integração.
  #
  # Cada chamada consome a próxima resposta do roteiro:
  # - String       -> texto devolvido como resposta completa;
  # - LlmResponse  -> devolvida como está (com usage, recusa, truncamento...)
  #                   e passa pelo mesmo LlmResponseContract do cliente real;
  # - Exception    -> é lançada (simula falha de rede/provedor).
  #
  # Guarda todos os prompts recebidos. Se o roteiro acabar, falha alto:
  # um teste nunca deve fazer mais chamadas ao LLM do que previu.
  class ScriptedLlmClient < LlmClient
    class ScriptExhausted < StandardError; end

    attr_reader :prompts

    def initialize(responses, response_contract: LlmResponseContract.new)
      @responses = responses.dup
      @response_contract = response_contract
      @prompts = []
      @lock = Mutex.new
    end

    def generate(prompt:)
      response = @lock.synchronize do
        @prompts << prompt
        raise ScriptExhausted, "No scripted LLM response for call #{@prompts.size}" if @responses.empty?

        @responses.shift
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

    def calls
      @prompts.size
    end

    def remaining
      @responses.size
    end
  end
end

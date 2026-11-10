module JobSearch
  # Decorator que mede cada chamada ao LLM: latência do provedor, tokens
  # reais, custo e orçamento do run.
  #
  # Usa #generate do cliente interno (que traz o usage) e só depois
  # aplica o LlmResponseContract: uma resposta truncada ou recusada
  # também foi cobrada e precisa entrar na conta antes de virar erro.
  #
  # Um por run, como o Tracer e o LlmBudget.
  class MeteredLlmClient < LlmClient
    def initialize(
      client:,
      tracer:,
      pricing_table:,
      budget:,
      model: nil,
      response_contract: LlmResponseContract.new
    )
      @client = client
      @tracer = tracer
      @pricing_table = pricing_table
      @budget = budget
      @model = model
      @response_contract = response_contract
    end

    def generate(prompt:)
      @budget.check!

      @tracer.span("llm.call") do |span|
        @client.generate(prompt: prompt).tap do |response|
          meter(response, span)
        end
      end
    end

    def complete(prompt:)
      @response_contract.text!(generate(prompt: prompt))
    end

    private

    def meter(response, span)
      model = response.model || @model
      usage = response.usage
      cost = @pricing_table.cost_usd(model: model, usage: usage)

      @budget.record(usage: usage, cost_usd: cost)

      span.set(:model, model.to_s) if model
      span.set(:response_status, response.status.to_s) if response.status
      span.set(:usage_reported, !usage.nil?)
      span.set(:cost_usd, cost) if cost

      return unless usage

      span.set(:input_tokens, usage.input_tokens)
      span.set(:cached_input_tokens, usage.cached_input_tokens)
      span.set(:output_tokens, usage.output_tokens)
      span.set(:total_tokens, usage.total_tokens)
    end
  end
end

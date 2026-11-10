module JobSearch
  # Tokens consumidos em uma chamada ao LLM.
  #
  # cached_input_tokens é a parte de input_tokens servida do cache do
  # provedor (cobrada mais barato); não é somada de novo ao total.
  LlmUsage = Data.define(:input_tokens, :output_tokens, :total_tokens, :cached_input_tokens) do
    def initialize(input_tokens:, output_tokens:, total_tokens: nil, cached_input_tokens: 0)
      super(
        input_tokens: input_tokens.to_i,
        output_tokens: output_tokens.to_i,
        total_tokens: (total_tokens || (input_tokens.to_i + output_tokens.to_i)).to_i,
        cached_input_tokens: cached_input_tokens.to_i
      )
    end
  end
end

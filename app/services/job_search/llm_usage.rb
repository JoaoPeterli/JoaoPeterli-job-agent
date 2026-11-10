module JobSearch
  # Tokens consumidos em uma chamada ao LLM.
  LlmUsage = Data.define(:input_tokens, :output_tokens, :total_tokens)
end

module JobSearch
  # A resposta veio incompleta (ex.: cortada por max_output_tokens).
  class LlmIncompleteResponseError < LlmResponseError; end
end

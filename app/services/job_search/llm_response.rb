module JobSearch
  # Resposta do LLM normalizada, independente do provedor.
  #
  # status: :completed, :incomplete, :failed (ou nil se o provedor não informar)
  # refusal: texto da recusa do modelo, quando houver
  # incomplete_reason: ex. :max_output_tokens, :content_filter
  # usage: tokens consumidos (base para métricas de custo)
  LlmResponse = Data.define(:text, :status, :refusal, :incomplete_reason, :usage) do
    def initialize(text:, status: :completed, refusal: nil, incomplete_reason: nil, usage: nil)
      super
    end
  end
end

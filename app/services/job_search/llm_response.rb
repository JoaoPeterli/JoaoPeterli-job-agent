module JobSearch
  # Resposta do LLM normalizada, independente do provedor.
  #
  # status: :completed, :incomplete, :failed (ou nil se o provedor não informar)
  # refusal: texto da recusa do modelo, quando houver
  # incomplete_reason: ex. :max_output_tokens, :content_filter
  # usage: tokens consumidos (base para métricas de custo)
  # model: modelo que de fato respondeu (ex.: snapshot datado), usado no preço
  LlmResponse = Data.define(:text, :status, :refusal, :incomplete_reason, :usage, :model) do
    def initialize(text:, status: :completed, refusal: nil, incomplete_reason: nil, usage: nil, model: nil)
      super
    end
  end
end

module JobSearch
  # Contrato mínimo que uma resposta do LLM precisa cumprir antes de ser
  # interpretada como plano. Separa "o modelo não entregou uma resposta
  # utilizável" (erro do canal) de "o plano entregue é inválido" (erro de
  # conteúdo, tratado pelo PlanOutputValidator e passível de reparo).
  class LlmResponseContract
    MAX_REFUSAL_LENGTH = 200

    TRUNCATED_MESSAGE =
      "LLM response was truncated at max_output_tokens. " \
      "Create a smaller plan with fewer steps and shorter names.".freeze

    def text!(response)
      check_refusal!(response)
      check_incomplete!(response)
      check_failed!(response)
      check_empty!(response)

      response.text
    end

    private

    def check_refusal!(response)
      return if response.refusal.to_s.strip.empty?

      refusal = response.refusal.to_s.strip[0, MAX_REFUSAL_LENGTH]

      raise LlmRefusalError, "LLM refused to plan: #{refusal}"
    end

    # Truncamento por limite de tokens é o único caso retryable: a nova
    # tentativa recebe a instrução de gerar um plano menor.
    def check_incomplete!(response)
      return unless response.status == :incomplete

      if response.incomplete_reason == :max_output_tokens
        raise LlmIncompleteResponseError.new(TRUNCATED_MESSAGE, retryable: true)
      end

      raise LlmIncompleteResponseError,
            "LLM response incomplete: #{response.incomplete_reason || 'unknown reason'}"
    end

    def check_failed!(response)
      return unless response.status == :failed

      raise LlmResponseError, "LLM response failed"
    end

    def check_empty!(response)
      return unless response.text.to_s.strip.empty?

      raise LlmResponseError, "LLM returned an empty response"
    end
  end
end

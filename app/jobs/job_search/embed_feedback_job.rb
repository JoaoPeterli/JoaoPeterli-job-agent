module JobSearch
  # Gera o embedding de uma marcação 👍/👎 fora do clique (a tela não
  # espera a OpenAI). Sem embedding, a marcação ainda vale na memória recente.
  class EmbedFeedbackJob < ApplicationJob
    queue_as :default
    discard_on ActiveRecord::RecordNotFound

    def perform(feedback_id)
      return unless Rails.configuration.x.rag_enabled

      JobIndex.default.embed_feedback(JobFeedback.find(feedback_id))
    rescue EmbeddingError => error
      Rails.logger.warn("[rag] feedback #{feedback_id} sem embedding: #{error.message}")
    end
  end
end

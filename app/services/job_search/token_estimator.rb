module JobSearch
  # Estimativa simples de tokens: ~4 caracteres por token em textos
  # em inglês/português. Não é exata, mas é determinística, barata e
  # suficiente para orçamento. Pode ser trocada por um tokenizer real
  # (ex.: tiktoken) sem mudar quem a usa.
  class TokenEstimator
    CHARS_PER_TOKEN = 4
    TRUNCATION_MARKER = "\n...[truncated]".freeze

    def count(text)
      (text.to_s.length / CHARS_PER_TOKEN.to_f).ceil
    end

    def truncate(text, max_tokens:)
      text = text.to_s
      return text if count(text) <= max_tokens

      max_chars = (max_tokens * CHARS_PER_TOKEN) - TRUNCATION_MARKER.length
      return "" if max_chars <= 0

      text[0, max_chars] + TRUNCATION_MARKER
    end
  end
end

module JobSearch
  # Heurísticas para padrões comuns de prompt injection (inglês e
  # português). Serve para rejeitar entradas óbvias e gerar sinal no log.
  #
  # NÃO é uma barreira de segurança: é fácil de contornar (paráfrase,
  # outro idioma, codificação). O sistema precisa continuar seguro mesmo
  # quando uma injeção passa por aqui.
  class InjectionDetector
    PATTERNS = {
      ignore_instructions: /\b(ignore|disregard|forget)\b.{0,30}\b(previous|prior|above|all|earlier)\b.{0,20}\b(instructions?|rules|prompts?)\b/,
      ignore_instructions_pt: /\b(ignore|desconsidere|esque[cç]a)\b.{0,30}\binstru[cç](ao|oes)\b/,
      new_instructions: /\b(new|updated|real)\s+instructions?\b|\bnovas\s+instru[cç]oes\b/,
      role_override: /\byou\s+are\s+now\b|\bvoce\s+agora\s+e\b|\bfrom\s+now\s+on\s+you\b/,
      prompt_reference: /\b(system|developer)\s+(prompt|message|instructions?)\b|\bprompt\s+do\s+sistema\b/,
      role_tag: %r{<\s*/?\s*(system|assistant|developer|user|untrusted_input)\b[^>]*>},
      role_prefix: /(^|\s)(system|assistant|developer)\s*:/
    }.freeze

    def detect(text)
      normalized = normalize(text)

      PATTERNS.filter_map do |name, pattern|
        name if normalized.match?(pattern)
      end
    end

    def suspicious?(text)
      detect(text).any?
    end

    private

    def normalize(text)
      text.to_s
        .unicode_normalize(:nfkd)
        .gsub(/\p{Mn}/, "")
        .gsub(UntrustedText::INVISIBLE, "")
        .downcase
        .gsub(/\s+/, " ")
    end
  end
end

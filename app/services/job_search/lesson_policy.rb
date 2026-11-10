module JobSearch
  # Decide quais lições persistidas podem voltar para um prompt.
  #
  # Lições vêm do banco e contêm texto ecoado de saídas antigas do LLM.
  # Sem filtro, um único run comprometido injetaria instruções em todos
  # os runs futuros com objetivo parecido (injeção armazenada).
  #
  # Allowlist: uma linha, curta, só caracteres comuns em mensagens dos
  # nossos validadores, e sem sinais de injeção.
  class LessonPolicy
    MAX_LENGTH = 160
    SAFE_CHARACTERS = /\A[\p{L}\p{N} _.,:;\-()'"$>\/]+\z/

    def initialize(detector: InjectionDetector.new)
      @detector = detector
    end

    def allowed?(lesson)
      lesson.is_a?(String) &&
        lesson.length.between?(1, MAX_LENGTH) &&
        lesson.match?(SAFE_CHARACTERS) &&
        !@detector.suspicious?(lesson)
    end
  end
end

module JobSearch
  # Monta o prompt a partir de seções respeitando um orçamento de tokens.
  #
  # 1. Seções em branco são ignoradas.
  # 2. Seção obrigatória acima do próprio max_tokens -> erro.
  #    Seção opcional acima do próprio max_tokens -> truncada.
  # 3. Todas as obrigatórias precisam caber juntas -> senão, erro.
  # 4. As opcionais entram na ordem enquanto houver espaço; as que não
  #    cabem são descartadas.
  # 5. A ordem original das seções é preservada no texto final.
  class ContextWindow
    SEPARATOR = "\n\n".freeze

    Result = Data.define(:text, :token_count, :truncated_sections, :dropped_sections)

    attr_reader :max_input_tokens

    def initialize(max_input_tokens:, estimator: TokenEstimator.new)
      unless max_input_tokens.is_a?(Integer) && max_input_tokens.positive?
        raise ArgumentError, "max_input_tokens must be a positive Integer"
      end

      @max_input_tokens = max_input_tokens
      @estimator = estimator
    end

    def build(sections)
      truncated = []
      sections = sections.reject(&:blank?).map do |section|
        apply_section_limit(section, truncated)
      end

      required_tokens = sections.select(&:required?).sum { |section| cost(section) }

      if required_tokens > @max_input_tokens
        raise ContextBudgetExceeded,
              "Required prompt sections need #{required_tokens} tokens " \
              "(limit: #{@max_input_tokens})"
      end

      remaining = @max_input_tokens - required_tokens
      dropped = []

      included = sections.select do |section|
        next true if section.required?

        if cost(section) <= remaining
          remaining -= cost(section)
          true
        else
          dropped << section.name
          false
        end
      end

      text = included.map(&:content).join(SEPARATOR)

      Result.new(
        text: text,
        token_count: @estimator.count(text),
        truncated_sections: truncated,
        dropped_sections: dropped
      )
    end

    private

    def apply_section_limit(section, truncated)
      return section if section.max_tokens.nil?
      return section if @estimator.count(section.content) <= section.max_tokens

      if section.required?
        raise ContextBudgetExceeded,
              "Prompt section #{section.name} exceeds " \
              "#{section.max_tokens} tokens"
      end

      truncated << section.name

      section.with(
        content: @estimator.truncate(section.content, max_tokens: section.max_tokens)
      )
    end

    # Custo inclui o separador para que a soma nunca subestime o total.
    def cost(section)
      @estimator.count(section.content + SEPARATOR)
    end
  end
end

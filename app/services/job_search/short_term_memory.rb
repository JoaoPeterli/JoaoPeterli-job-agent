module JobSearch
  # Memória de curto prazo de uma execução do agente (um run_id).
  #
  # Guarda eventos em ordem cronológica, como resumos curtos, nunca o
  # dado bruto das ferramentas: a memória existe para ser lida (por
  # pessoas e pelo LLM), e cada caractere aqui pode virar token no
  # próximo prompt.
  #
  # É uma janela deslizante: ao passar de max_entries, os eventos mais
  # antigos são descartados. A sequência continua crescendo, então dá
  # para perceber que houve descarte (a primeira seq deixa de ser 1).
  class ShortTermMemory
    Entry = Data.define(:seq, :kind, :content) do
      def to_s
        "[#{kind}] #{content}"
      end
    end

    DEFAULT_MAX_ENTRIES = 50
    MAX_CONTENT_LENGTH = 500

    # entries: usado para restaurar uma memória persistida. A sequência
    # continua a partir do maior seq restaurado.
    def initialize(max_entries: DEFAULT_MAX_ENTRIES, entries: [])
      unless max_entries.is_a?(Integer) && max_entries.positive?
        raise ArgumentError, "max_entries must be a positive Integer"
      end

      @max_entries = max_entries
      @entries = entries.last(max_entries)
      @seq = entries.map(&:seq).max || 0
    end

    def record(kind, content)
      @seq += 1

      entry = Entry.new(
        seq: @seq,
        kind: kind.to_sym,
        content: summarize(content)
      )

      @entries << entry
      @entries.shift while @entries.length > @max_entries

      entry
    end

    def entries
      @entries.dup.freeze
    end

    def of_kind(*kinds)
      kinds = kinds.map(&:to_sym)

      @entries.select { |entry| kinds.include?(entry.kind) }
    end

    def size
      @entries.length
    end

    def empty?
      @entries.empty?
    end

    def evicted_count
      @seq - @entries.length
    end

    private

    def summarize(content)
      text = content.to_s.gsub(/\s+/, " ").strip
      return text if text.length <= MAX_CONTENT_LENGTH

      "#{text[0, MAX_CONTENT_LENGTH - 3]}..."
    end
  end
end

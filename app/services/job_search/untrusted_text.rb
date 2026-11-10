module JobSearch
  # Tratamento de texto que não foi escrito por nós: entrada do usuário,
  # texto ecoado da saída do LLM, memória persistida, resultado de APIs.
  #
  # sanitize: remove caracteres de controle e invisíveis (zero-width,
  #           bidi override), normaliza Unicode e limita o tamanho.
  # wrap:     delimita o texto com <untrusted_input>, neutralizando tags
  #           iguais dentro do conteúdo para que ele não "feche" o bloco.
  #
  # Delimitar não impede injeção: é um sinal para o modelo, que o prompt
  # reforça com uma regra explícita. A barreira real está fora do LLM
  # (ferramentas registradas, argumentos validados, permissões).
  module UntrustedText
    TAG = "untrusted_input".freeze
    TAG_PATTERN = %r{<\s*/?\s*#{TAG}[^>]*>}i
    REMOVED_TAG = "[removed tag]".freeze

    # Cc = controle (exceto \n e \t), Cf = formatação invisível
    # (zero-width, bidi), Co/Cs = uso privado/surrogates.
    INVISIBLE = /[\p{Cf}\p{Co}\p{Cs}]|[\p{Cc}&&[^\n\t]]/

    module_function

    def sanitize(text, max_length:, single_line: false)
      clean = text.to_s
        .unicode_normalize(:nfkc)
        .gsub(INVISIBLE, "")
        .gsub("\t", " ")

      clean =
        if single_line
          clean.gsub(/\s+/, " ")
        else
          clean.gsub(/[ ]+/, " ").gsub(/\n{3,}/, "\n\n")
        end

      clean = clean.strip
      return clean if clean.length <= max_length

      "#{clean[0, max_length - 3]}..."
    end

    def wrap(text, source:)
      content = text.to_s.gsub(TAG_PATTERN, REMOVED_TAG)

      %(<#{TAG} source="#{source}">\n#{content}\n</#{TAG}>)
    end
  end
end

module JobSearch
  # Um pedaço do prompt.
  #
  # required: true  -> entra inteiro ou o prompt não é montado.
  # required: false -> pode ser truncado (max_tokens) ou descartado
  #                    quando o orçamento acaba.
  PromptSection = Data.define(:name, :content, :required, :max_tokens) do
    def initialize(name:, content:, required: true, max_tokens: nil)
      super
    end

    def required?
      required
    end

    def blank?
      content.to_s.strip.empty?
    end
  end
end

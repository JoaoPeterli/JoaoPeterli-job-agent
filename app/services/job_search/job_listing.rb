module JobSearch
  # Vaga normalizada, igual para todas as fontes. O link só é aceito se
  # for http(s): dados externos nunca viram javascript: num href.
  JobListing = Data.define(:title, :company, :url, :source, :location, :remote, :published_at, :tags) do
    def self.build(title:, url:, source:, company: nil, location: nil, remote: false, published_at: nil, tags: [])
      new(
        title: clean(title),
        company: clean(company),
        url: safe_url(url),
        source: source,
        location: clean(location),
        remote: remote == true,
        published_at: published_at,
        tags: Array(tags).map { |tag| clean(tag) }.compact.uniq
      )
    end

    def self.clean(text)
      value = text.to_s.gsub(/\s+/, " ").strip
      value.empty? ? nil : value
    end

    def self.safe_url(url)
      uri = URI.parse(url.to_s.strip)
      uri.is_a?(URI::HTTP) && uri.host.present? ? uri.to_s : nil
    rescue URI::InvalidURIError
      nil
    end

    # Formato da saída da ferramenta (vai para o resultado do run em JSON).
    def to_tool_output
      {
        title: title,
        company: company,
        remote: remote,
        url: url,
        source: source,
        location: location,
        published_at: published_at&.iso8601,
        tags: tags.first(8)
      }
    end

    # Chave para remover a mesma vaga publicada em mais de uma fonte (e
    # para ligar a vaga ao feedback do usuário, JobFeedback#job_key).
    def self.key_for(title:, company:)
      [ title, company ].map { |part| part.to_s.downcase.gsub(/[^[:alnum:]]/, "") }.join("|")
    end

    def dedup_key
      self.class.key_for(title: title, company: company)
    end
  end
end

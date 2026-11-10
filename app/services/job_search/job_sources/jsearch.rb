module JobSearch
  module JobSources
    # JSearch (OpenWeb Ninja, via RapidAPI): lê o Google for Jobs, onde
    # aparecem as vagas do LinkedIn, Indeed, Glassdoor e sites de empresas.
    # É uma busca por consulta (não um feed). O plano grátis tem ~200
    # consultas/mês, por isso cada consulta fica 6 h em cache.
    #
    # JSEARCH_API_KEY: chave do RapidAPI (obrigatória; sem ela a fonte nem
    # é ligada, ver config/application.rb). JSEARCH_COUNTRY: país (padrão br).
    class Jsearch
      NAME = "JSearch".freeze
      HOMEPAGE = "https://www.openwebninja.com/api/jsearch".freeze
      HOST = "jsearch.p.rapidapi.com".freeze
      # API v5: o antigo /search responde 404.
      SEARCH_PATH = "/search-v2".freeze
      RELATIVE_UNITS = {
        /\A(min|minuto|minute)/ => 1.minute, /\A(h|hora|hour)/ => 1.hour, /\A(dia|day)/ => 1.day,
        /\A(semana|week)/ => 1.week, /\A(m[eê]s|meses|month)/ => 1.month
      }.freeze
      CACHE_TTL = 6.hours

      def initialize(fetcher:, api_key: ENV["JSEARCH_API_KEY"], country: ENV.fetch("JSEARCH_COUNTRY", "br"))
        @fetcher = fetcher
        @api_key = api_key.presence
        @country = country.to_s.downcase.presence || "br"
      end

      def search(technology:, remote:)
        raise JobSourceError, "#{NAME}: JSEARCH_API_KEY is not set" unless @api_key

        body = @fetcher.get(search_url(technology, remote), ttl: CACHE_TTL,
                            headers: { "X-RapidAPI-Key" => @api_key, "X-RapidAPI-Host" => HOST })
        data = JSON.parse(body)
        jobs = jobs_from(data)
        raise JobSourceError, "#{NAME}: unexpected response" unless jobs

        jobs.map { |job| build(job) }
      rescue JSON::ParserError => error
        raise JobSourceError, "#{NAME}: invalid JSON (#{error.message.truncate(80)})"
      end

      private

      # v5: {"data": {"jobs": [...], "cursor": "..."}}; versões antigas: {"data": [...]}.
      def jobs_from(data)
        return unless data.is_a?(Hash)

        payload = data["data"]
        payload = payload["jobs"] if payload.is_a?(Hash)
        payload if payload.is_a?(Array)
      end

      def search_url(technology, remote)
        # num_pages 1: cada página (até 10 vagas) consome uma consulta do plano.
        query = { query: "#{technology} developer", num_pages: 1, country: @country, date_posted: "month" }
        query[:work_from_home] = true if remote

        "https://#{HOST}#{SEARCH_PATH}?#{query.to_query}"
      end

      def build(job)
        publisher = job["job_publisher"].presence

        JobListing.build(
          title: job["job_title"],
          company: job["employer_name"],
          url: job["job_apply_link"].presence || job["job_google_link"],
          # "LinkedIn via JSearch": o crédito vai para o site de origem e para o agregador.
          source: publisher ? "#{publisher} via #{NAME}" : NAME,
          location: job["job_location"].presence || [ job["job_city"], job["job_country"] ].compact_blank.join(", "),
          remote: job["job_is_remote"] == true,
          published_at: posted_at(job),
          tags: [ job["job_employment_type"] ]
        )
      end

      def posted_at(job)
        if job["job_posted_at_timestamp"].present?
          Time.zone.at(job["job_posted_at_timestamp"].to_i)
        elsif job["job_posted_at_datetime_utc"].present?
          Time.zone.parse(job["job_posted_at_datetime_utc"].to_s)
        else
          relative_time(job["job_posted_at"])
        end
      rescue ArgumentError
        nil
      end

      # A v5 costuma trazer só o texto relativo, no idioma do país:
      # "há 8 dias", "há 1 hora", "3 days ago".
      def relative_time(text)
        amount, unit = text.to_s.downcase.match(/(\d+)\s*([[:alpha:]]+)/)&.captures
        return unless amount

        step = RELATIVE_UNITS.find { |pattern, _| unit.match?(pattern) }&.last
        step && Time.current - (amount.to_i * step)
      end
    end
  end
end

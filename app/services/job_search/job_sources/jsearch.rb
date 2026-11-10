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
        raise JobSourceError, "#{NAME}: unexpected response" unless data.is_a?(Hash) && data["data"].is_a?(Array)

        data["data"].map { |job| build(job) }
      rescue JSON::ParserError => error
        raise JobSourceError, "#{NAME}: invalid JSON (#{error.message.truncate(80)})"
      end

      private

      def search_url(technology, remote)
        query = { query: "#{technology} developer", page: 1, num_pages: 1, country: @country, date_posted: "month" }
        query[:work_from_home] = true if remote

        "https://#{HOST}/search?#{query.to_query}"
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
        end
      rescue ArgumentError
        nil
      end
    end
  end
end

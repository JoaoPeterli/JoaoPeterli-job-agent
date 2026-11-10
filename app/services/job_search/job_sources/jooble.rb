module JobSearch
  module JobSources
    # jooble.org/api — agregador mundial. A chave vai NA URL (formato da
    # API), por isso o cache usa uma chave própria e os erros citam só o host.
    # JOOBLE_API_KEY: obrigatória (sem ela a fonte nem é ligada).
    # JOOBLE_LOCATION: local da busca (padrão "Brasil").
    class Jooble
      NAME = "Jooble".freeze
      HOMEPAGE = "https://jooble.org".freeze
      CACHE_TTL = 6.hours

      def initialize(fetcher:, api_key: ENV["JOOBLE_API_KEY"], location: ENV.fetch("JOOBLE_LOCATION", "Brasil"))
        @fetcher = fetcher
        @api_key = api_key.presence
        @location = location.to_s
      end

      def search(technology:, remote:)
        raise JobSourceError, "#{NAME}: JOOBLE_API_KEY is not set" unless @api_key

        body = { keywords: [ technology, ("remoto" if remote) ].compact.join(" "), location: @location }
        data = JSON.parse(@fetcher.post_json("https://jooble.org/api/#{@api_key}", body: body, ttl: CACHE_TTL,
                                             cache_key: "jooble/#{body.to_query}"))
        jobs = data.is_a?(Hash) ? data["jobs"] : nil
        raise JobSourceError, "#{NAME}: unexpected response" unless jobs.is_a?(Array)

        jobs.filter_map { |job| build(job, remote) }
      rescue JSON::ParserError => error
        raise JobSourceError, "#{NAME}: invalid JSON (#{error.message.truncate(80)})"
      end

      private

      def build(job, remote)
        location = job["location"].to_s

        JobListing.build(
          title: job["title"],
          company: job["company"],
          url: job["link"],
          source: job["source"].present? ? "#{job['source']} via #{NAME}" : NAME,
          location: location,
          remote: location.match?(/remot|home office|anywhere/i) || job["title"].to_s.match?(/remot|home office/i),
          published_at: (Time.zone.parse(job["updated"].to_s) if job["updated"].present?),
          tags: [ job["type"] ]
        )
      rescue ArgumentError
        nil
      end
    end
  end
end

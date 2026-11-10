module JobSearch
  module JobSources
    # remoteok.com/api — termos: citar "Remote OK" como fonte e linkar a
    # vaga original (o link de cada vaga aponta para o Remote OK).
    class RemoteOk
      NAME = "Remote OK".freeze
      HOMEPAGE = "https://remoteok.com".freeze
      FEED_URL = "https://remoteok.com/api".freeze

      def initialize(fetcher:)
        @fetcher = fetcher
      end

      def fetch
        # O primeiro item é o aviso legal, não uma vaga.
        JSON.parse(@fetcher.get(FEED_URL)).drop(1).filter_map { |job| build(job) if job["position"] }
      rescue JSON::ParserError => error
        raise JobSourceError, "#{NAME}: invalid JSON (#{error.message.truncate(80)})"
      end

      private

      def build(job)
        JobListing.build(
          title: job["position"],
          company: job["company"],
          url: job["url"],
          source: NAME,
          location: job["location"].presence || "Remoto",
          remote: true,
          published_at: Time.zone.parse(job["date"].to_s),
          tags: job["tags"]
        )
      end
    end
  end
end

module JobSearch
  module JobSources
    # arbeitnow.com/api/job-board-api — API pública, atualizada a cada hora.
    # Termos: não abusar e linkar de volta para o site.
    class Arbeitnow
      NAME = "Arbeitnow".freeze
      HOMEPAGE = "https://www.arbeitnow.com".freeze
      FEED_URL = "https://www.arbeitnow.com/api/job-board-api".freeze

      def initialize(fetcher:)
        @fetcher = fetcher
      end

      def fetch
        JSON.parse(@fetcher.get(FEED_URL)).fetch("data", []).map { |job| build(job) }
      rescue JSON::ParserError, TypeError => error
        raise JobSourceError, "#{NAME}: invalid JSON (#{error.message.truncate(80)})"
      end

      private

      def build(job)
        JobListing.build(
          title: job["title"],
          company: job["company_name"],
          url: job["url"],
          source: NAME,
          location: job["location"],
          remote: job["remote"] == true,
          published_at: job["created_at"] && Time.zone.at(job["created_at"].to_i),
          tags: Array(job["tags"]) + Array(job["job_types"])
        )
      end
    end
  end
end

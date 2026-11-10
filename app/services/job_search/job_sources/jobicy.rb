module JobSearch
  module JobSources
    # jobicy.com/api/v2/remote-jobs — vagas remotas, busca por tag. Termos:
    # creditar o Jobicy com link e mandar a candidatura para a URL original.
    # Pedem no máximo uma consulta por hora: cache de 1 h por tag.
    class Jobicy
      NAME = "Jobicy".freeze
      HOMEPAGE = "https://jobicy.com".freeze
      CACHE_TTL = 1.hour

      def initialize(fetcher:)
        @fetcher = fetcher
      end

      def search(technology:, remote:)
        url = "https://jobicy.com/api/v2/remote-jobs?#{{ count: 50, tag: technology.to_s.strip.downcase }.to_query}"
        data = JSON.parse(@fetcher.get(url, ttl: CACHE_TTL))
        jobs = data.is_a?(Hash) ? data["jobs"] : nil
        raise JobSourceError, "#{NAME}: unexpected response" unless jobs.is_a?(Array)

        jobs.map { |job| build(job) }
      rescue JSON::ParserError => error
        raise JobSourceError, "#{NAME}: invalid JSON (#{error.message.truncate(80)})"
      end

      private

      def build(job)
        JobListing.build(
          title: job["jobTitle"],
          company: job["companyName"],
          url: job["url"],
          source: NAME,
          location: job["jobGeo"],
          remote: true,
          published_at: (Time.zone.parse(job["pubDate"].to_s) if job["pubDate"].present?),
          tags: Array(job["jobIndustry"]) + Array(job["jobType"]) + [ job["jobLevel"] ]
        )
      end
    end
  end
end

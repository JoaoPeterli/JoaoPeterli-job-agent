module JobSearch
  module JobSources
    # himalayas.app/jobs/api/search — vagas remotas com busca por palavra-chave.
    class Himalayas
      NAME = "Himalayas".freeze
      HOMEPAGE = "https://himalayas.app".freeze
      CACHE_TTL = 1.hour

      def initialize(fetcher:)
        @fetcher = fetcher
      end

      def search(technology:, remote:)
        url = "https://himalayas.app/jobs/api/search?#{{ q: technology.to_s.strip, limit: 20 }.to_query}"
        data = JSON.parse(@fetcher.get(url, ttl: CACHE_TTL))
        jobs = data.is_a?(Hash) ? data["jobs"] : nil
        raise JobSourceError, "#{NAME}: unexpected response" unless jobs.is_a?(Array)

        jobs.map { |job| build(job) }
      rescue JSON::ParserError => error
        raise JobSourceError, "#{NAME}: invalid JSON (#{error.message.truncate(80)})"
      end

      private

      # Algumas vagas aceitam 70+ países: mostra 3 e o total do resto.
      def location(countries)
        countries = Array(countries)
        return "Qualquer lugar" if countries.empty?

        shown = countries.first(3).join(", ")
        countries.size > 3 ? "#{shown} +#{countries.size - 3}" : shown
      end

      def build(job)
        JobListing.build(
          title: job["title"],
          company: job["companyName"],
          url: job["applicationLink"].presence || job["guid"],
          source: NAME,
          location: location(job["locationRestrictions"]),
          remote: true,
          published_at: (Time.zone.at(job["pubDate"].to_i) if job["pubDate"].present?),
          tags: Array(job["categories"]).map { |category| category.to_s.tr("-", " ") } + Array(job["seniority"])
        )
      end
    end
  end
end

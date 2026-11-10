module JobSearch
  module JobSources
    # api.lever.co/v0/postings — API pública oficial (vagas publicadas).
    class Lever < CompanyBoards
      NAME = "Lever".freeze
      HOMEPAGE = "https://www.lever.co".freeze
      CONFIG_KEY = :lever

      private

      def board_url(slug) = "https://api.lever.co/v0/postings/#{slug}?mode=json"

      def jobs_in(data) = data.is_a?(Array) ? data : raise(TypeError)

      def build(job, slug:, name:)
        categories = job["categories"].is_a?(Hash) ? job["categories"] : {}

        JobListing.build(
          title: job["text"],
          company: name,
          url: job["hostedUrl"],
          source: "#{name} · #{NAME}",
          location: categories["location"],
          remote: job["workplaceType"] == "remote" || remote_text?(categories["location"]),
          published_at: job["createdAt"] && Time.zone.at(job["createdAt"].to_i / 1000),
          tags: categories.values_at("department", "team", "commitment")
        )
      end
    end
  end
end

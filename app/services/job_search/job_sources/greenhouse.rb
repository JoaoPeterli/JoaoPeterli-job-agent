module JobSearch
  module JobSources
    # boards-api.greenhouse.io — API pública oficial de job boards (só leitura).
    class Greenhouse < CompanyBoards
      NAME = "Greenhouse".freeze
      HOMEPAGE = "https://www.greenhouse.com".freeze
      CONFIG_KEY = :greenhouse

      private

      def board_url(slug) = "https://boards-api.greenhouse.io/v1/boards/#{slug}/jobs"

      def jobs_in(data) = data.fetch("jobs")

      def build(job, slug:, name:)
        location = job.dig("location", "name")

        JobListing.build(
          title: job["title"],
          company: job["company_name"].presence || name,
          url: job["absolute_url"],
          source: "#{name} · #{NAME}",
          location: location,
          remote: remote_text?(location),
          published_at: parse_time(job["first_published"].presence || job["updated_at"]),
          tags: Array(job["metadata"]).filter_map { |meta| meta["value"] if meta["value"].is_a?(String) }
        )
      end
    end
  end
end

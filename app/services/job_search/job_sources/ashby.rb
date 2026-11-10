module JobSearch
  module JobSources
    # api.ashbyhq.com/posting-api/job-board — API pública oficial de vagas.
    class Ashby < CompanyBoards
      NAME = "Ashby".freeze
      HOMEPAGE = "https://www.ashbyhq.com".freeze
      CONFIG_KEY = :ashby

      private

      def board_url(slug) = "https://api.ashbyhq.com/posting-api/job-board/#{slug}"

      def jobs_in(data) = data.fetch("jobs").select { |job| job["isListed"] != false }

      def build(job, slug:, name:)
        JobListing.build(
          title: job["title"],
          company: name,
          url: job["jobUrl"],
          source: "#{name} · #{NAME}",
          location: job["location"],
          remote: job["isRemote"] == true || job["workplaceType"].to_s.casecmp?("remote") || remote_text?(job["location"]),
          published_at: parse_time(job["publishedAt"]),
          tags: [ job["department"], job["team"], job["employmentType"] ]
        )
      end
    end
  end
end

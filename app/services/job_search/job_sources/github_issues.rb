module JobSearch
  module JobSources
    # Vagas brasileiras publicadas como issues no GitHub (comunidades
    # backend-br e frontendbr). API oficial: 60 req/h sem token; com
    # GITHUB_TOKEN, 5.000 req/h. Título no formato "[Local] Cargo - Empresa".
    class GithubIssues
      NAME = "GitHub".freeze
      HOMEPAGE = "https://github.com/backend-br/vagas".freeze
      REPOSITORIES = %w[backend-br/vagas frontendbr/vagas].freeze
      REMOTE = /\bremot[oa]\b/i

      def initialize(fetcher:, repositories: REPOSITORIES, token: ENV["GITHUB_TOKEN"])
        @fetcher = fetcher
        @repositories = repositories
        @token = token.presence
      end

      def fetch
        @repositories.flat_map do |repository|
          issues = JSON.parse(@fetcher.get(issues_url(repository), headers: headers))
          issues.reject { |issue| issue.key?("pull_request") }.map { |issue| build(issue, repository) }
        end
      rescue JSON::ParserError, TypeError => error
        raise JobSourceError, "#{NAME}: invalid JSON (#{error.message.truncate(80)})"
      end

      private

      def issues_url(repository)
        "https://api.github.com/repos/#{repository}/issues?state=open&per_page=100"
      end

      def headers
        base = { "Accept" => "application/vnd.github+json" }
        @token ? base.merge("Authorization" => "Bearer #{@token}") : base
      end

      def build(issue, repository)
        raw_title = issue["title"].to_s
        location = raw_title[/\A\s*\[([^\]]+)\]/, 1]
        title = raw_title.sub(/\A\s*\[[^\]]+\]\s*/, "")
        parts = title.split(/\s+-\s+/)
        company = parts.size > 1 ? parts.pop : nil
        labels = Array(issue["labels"]).filter_map { |label| label["name"] }

        JobListing.build(
          title: parts.join(" - "),
          company: company,
          url: issue["html_url"],
          source: "#{NAME} · #{repository.split('/').first}",
          location: location,
          remote: labels.any? { |label| label.match?(REMOTE) } || location.to_s.match?(REMOTE),
          published_at: Time.zone.parse(issue["created_at"].to_s),
          tags: labels - [ "verificada" ]
        )
      end
    end
  end
end

require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_fetcher")

RSpec.describe JobSearch::JobSources::GithubIssues do
  let(:url) { "https://api.github.com/repos/backend-br/vagas/issues?state=open&per_page=100" }
  let(:fetcher) { JobSearch::FakeFetcher.new(url => JobSearch::FakeFetcher.fixture("github_issues.json")) }

  def source(token: nil)
    described_class.new(fetcher: fetcher, repositories: [ "backend-br/vagas" ], token: token)
  end

  it "reads location, role and company from '[Local] Role - Company' titles" do
    job = source.fetch.first

    expect(job).to have_attributes(
      title: "Desenvolvedor(a) Backend Pleno - White Label e Plataforma", company: "Mimix AI",
      location: "Remoto", remote: true, source: "GitHub · backend-br",
      url: "https://github.com/backend-br/vagas/issues/12494"
    )
    expect(job.tags).to include("PJ", "Pleno")
    expect(job.tags).not_to include("verificada")
  end

  it "keeps the company empty when the title has no separator" do
    expect(source.fetch.third.company).to be_nil
  end

  it "skips pull requests" do
    issues = JSON.parse(JobSearch::FakeFetcher.fixture("github_issues.json"))
    issues.first["pull_request"] = { "url" => "x" }
    fetcher = JobSearch::FakeFetcher.new(url => issues.to_json)

    expect(described_class.new(fetcher: fetcher, repositories: [ "backend-br/vagas" ], token: nil).fetch.size).to eq(2)
  end

  it "sends the token only when configured" do
    source.fetch
    expect(fetcher.requests.last[:headers]).not_to have_key("Authorization")

    source(token: "t0k3n").fetch
    expect(fetcher.requests.last[:headers]).to include("Authorization" => "Bearer t0k3n")
  end
end

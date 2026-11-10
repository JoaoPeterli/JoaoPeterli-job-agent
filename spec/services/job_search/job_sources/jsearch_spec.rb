require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_fetcher")

RSpec.describe JobSearch::JobSources::Jsearch do
  let(:base) { "https://jsearch.p.rapidapi.com/search?" }
  let(:remote_url) { base + { query: "Ruby developer", page: 1, num_pages: 1, country: "br", date_posted: "month", work_from_home: true }.to_query }
  let(:fetcher) { JobSearch::FakeFetcher.new(remote_url => JobSearch::FakeFetcher.fixture("jsearch.json")) }

  def source(api_key: "k3y", fetcher: self.fetcher, country: "br")
    described_class.new(fetcher: fetcher, api_key: api_key, country: country)
  end

  it "maps jobs crediting the original publisher (LinkedIn, Indeed...)" do
    first, second = source.search(technology: "Ruby", remote: true)

    expect(first).to have_attributes(
      title: "Desenvolvedor Ruby on Rails Sênior", company: "Empresa Exemplo", source: "LinkedIn via JSearch",
      url: "https://www.linkedin.com/jobs/view/123", remote: true, location: "São Paulo, SP",
      published_at: Time.zone.at(1_794_240_000), tags: [ "FULLTIME" ]
    )
    expect(second).to have_attributes(
      source: "Indeed via JSearch", url: "https://www.google.com/search?q=job", remote: false,
      location: "Curitiba, BR", published_at: Time.zone.parse("2026-11-05T12:00:00Z")
    )
  end

  it "sends the key in headers (never in the URL) and caches each query for 6 hours" do
    source.search(technology: "Ruby", remote: true)

    request = fetcher.requests.last
    expect(request[:url]).not_to include("k3y")
    expect(request[:headers]).to eq("X-RapidAPI-Key" => "k3y", "X-RapidAPI-Host" => "jsearch.p.rapidapi.com")
    expect(request[:ttl]).to eq(6.hours)
  end

  it "asks for remote jobs only when the search is remote" do
    onsite_url = base + { query: "Ruby developer", page: 1, num_pages: 1, country: "br", date_posted: "month" }.to_query
    fetcher = JobSearch::FakeFetcher.new(onsite_url => JobSearch::FakeFetcher.fixture("jsearch.json"))

    expect(source(fetcher: fetcher).search(technology: "Ruby", remote: false).size).to eq(2)
  end

  it "fails as a source error without a key or with an unexpected payload" do
    expect { source(api_key: nil).search(technology: "Ruby", remote: true) }
      .to raise_error(JobSearch::JobSourceError, /JSEARCH_API_KEY/)

    fetcher = JobSearch::FakeFetcher.new(remote_url => '{"message":"You are not subscribed to this API."}')
    expect { source(fetcher: fetcher).search(technology: "Ruby", remote: true) }
      .to raise_error(JobSearch::JobSourceError, /unexpected response/)
  end
end

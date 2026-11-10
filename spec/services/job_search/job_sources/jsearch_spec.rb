require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_fetcher")

RSpec.describe JobSearch::JobSources::Jsearch do
  include ActiveSupport::Testing::TimeHelpers

  let(:base) { "https://jsearch.p.rapidapi.com/search-v2?" }
  let(:remote_url) { base + { query: "Ruby developer", num_pages: 1, country: "br", date_posted: "month", work_from_home: true }.to_query }
  # Amostra real (reduzida) da API v5: {"data": {"jobs": [...], "cursor": ...}}.
  let(:fetcher) { JobSearch::FakeFetcher.new(remote_url => JobSearch::FakeFetcher.fixture("jsearch.json")) }

  def source(api_key: "k3y", fetcher: self.fetcher, country: "br")
    described_class.new(fetcher: fetcher, api_key: api_key, country: country)
  end

  it "maps v5 jobs crediting the original publisher (Gupy, Catho, LinkedIn...)" do
    travel_to Time.zone.parse("2026-11-10 12:00") do
      first, second, third = source.search(technology: "Ruby", remote: true)

      expect(first).to have_attributes(
        title: "Pessoa Desenvolvedora Ruby on Rails - Pleno", company: "FCamara",
        source: "FCamara - Gupy via JSearch", remote: true, location: "Qualquer lugar",
        url: start_with("https://fcamara.gupy.io/jobs/"), published_at: 8.days.ago, tags: [ "Tempo integral" ]
      )
      expect(second).to have_attributes(source: "Catho via JSearch", remote: false, location: "Goiás, GO (+35)",
                                        published_at: nil)
      # Sem link de candidatura: cai no link do Google; data pelo timestamp.
      expect(third).to have_attributes(url: start_with("https://www.google.com/"), published_at: Time.zone.at(1_794_240_000))
    end
  end

  it "reads relative dates in Portuguese and English" do
    travel_to Time.zone.parse("2026-11-10 12:00") do
      parse = ->(text) { source.send(:relative_time, text) }

      expect(parse.("há 1 hora")).to eq(1.hour.ago)
      expect(parse.("há 3 semanas")).to eq(3.weeks.ago)
      expect(parse.("2 days ago")).to eq(2.days.ago)
      expect(parse.("há 2 meses")).to eq(2.months.ago)
      expect(parse.("ontem")).to be_nil
      expect(parse.(nil)).to be_nil
    end
  end

  it "still accepts the older shape with the jobs directly in data" do
    jobs = JSON.parse(JobSearch::FakeFetcher.fixture("jsearch.json")).dig("data", "jobs")
    fetcher = JobSearch::FakeFetcher.new(remote_url => { "status" => "OK", "data" => jobs }.to_json)

    expect(source(fetcher: fetcher).search(technology: "Ruby", remote: true).size).to eq(3)
  end

  it "sends the key in headers (never in the URL) and caches each query for 6 hours" do
    source.search(technology: "Ruby", remote: true)

    request = fetcher.requests.last
    expect(request[:url]).not_to include("k3y")
    expect(request[:headers]).to eq("X-RapidAPI-Key" => "k3y", "X-RapidAPI-Host" => "jsearch.p.rapidapi.com")
    expect(request[:ttl]).to eq(6.hours)
  end

  it "asks for remote jobs only when the search is remote" do
    onsite_url = base + { query: "Ruby developer", num_pages: 1, country: "br", date_posted: "month" }.to_query
    fetcher = JobSearch::FakeFetcher.new(onsite_url => JobSearch::FakeFetcher.fixture("jsearch.json"))

    expect(source(fetcher: fetcher).search(technology: "Ruby", remote: false).size).to eq(3)
  end

  it "fails as a source error without a key or with an unexpected payload" do
    expect { source(api_key: nil).search(technology: "Ruby", remote: true) }
      .to raise_error(JobSearch::JobSourceError, /JSEARCH_API_KEY/)

    fetcher = JobSearch::FakeFetcher.new(remote_url => '{"message":"You are not subscribed to this API."}')
    expect { source(fetcher: fetcher).search(technology: "Ruby", remote: true) }
      .to raise_error(JobSearch::JobSourceError, /unexpected response/)
  end
end

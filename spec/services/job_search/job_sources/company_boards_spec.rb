require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_fetcher")

RSpec.describe "Company boards (Greenhouse, Lever, Ashby)" do
  let(:serial) { JobSearch::ParallelRunner.new(max_parallel: 1) }
  let(:fixture) { ->(name) { JobSearch::FakeFetcher.fixture(name) } }

  describe JobSearch::JobSources::Greenhouse do
    let(:url) { "https://boards-api.greenhouse.io/v1/boards/vtex/jobs" }

    it "maps the public board crediting company and ATS" do
      fetcher = JobSearch::FakeFetcher.new(url => fixture.("greenhouse.json"))
      job = described_class.new(fetcher: fetcher, companies: { "vtex" => "VTEX" }, runner: serial).fetch.first

      expect(job).to have_attributes(
        title: "Analista Administrativo Jurídico (Exclusivo para pessoas com deficiência)", company: "VTEX",
        source: "VTEX · Greenhouse", location: "Rio de Janeiro; São Paulo, Sao Paulo, Brazil", remote: false,
        url: "https://job-boards.greenhouse.io/vtex/jobs/6234888004",
        published_at: Time.zone.parse("2026-10-26T13:38:41-04:00")
      )
      expect(job.tags).to include("Junior")
    end

    it "skips a company whose board fails and keeps the others" do
      other = "https://boards-api.greenhouse.io/v1/boards/missing/jobs"
      fetcher = JobSearch::FakeFetcher.new(url => fixture.("greenhouse.json"), other => JobSearch::JobSourceError.new("404"))

      jobs = described_class.new(fetcher: fetcher, companies: { "missing" => "X", "vtex" => "VTEX" }, runner: serial).fetch

      expect(jobs.size).to eq(2)
    end

    it "fails only when every board fails" do
      fetcher = JobSearch::FakeFetcher.new(url => JobSearch::JobSourceError.new("boom"))

      expect { described_class.new(fetcher: fetcher, companies: { "vtex" => "VTEX" }, runner: serial).fetch }
        .to raise_error(JobSearch::JobSourceError, /Greenhouse: every board failed/)
    end

    it "reads the company list from config/job_companies.yml" do
      expect(described_class.companies(:greenhouse)).to include("vtex" => "VTEX", "quintoandar" => "QuintoAndar")
    end
  end

  describe JobSearch::JobSources::Lever do
    it "maps postings with workplace type, categories and creation time" do
      url = "https://api.lever.co/v0/postings/neon?mode=json"
      fetcher = JobSearch::FakeFetcher.new(url => fixture.("lever.json"))

      remote, onsite = described_class.new(fetcher: fetcher, companies: { "neon" => "Neon" }, runner: serial).fetch

      expect(remote).to have_attributes(company: "Neon", source: "Neon · Lever", location: "Remoto", remote: true,
                                        published_at: Time.zone.at(1_792_708_355),
                                        url: start_with("https://jobs.lever.co/neon/"))
      expect(remote.tags).to include("Product & Marketing", "CLT")
      expect(onsite).to have_attributes(location: "São Paulo", remote: false)
    end
  end

  describe JobSearch::JobSources::Ashby do
    it "maps listed jobs only and detects remote by flag or location" do
      url = "https://api.ashbyhq.com/posting-api/job-board/supabase"
      fetcher = JobSearch::FakeFetcher.new(url => fixture.("ashby.json"))

      jobs = described_class.new(fetcher: fetcher, companies: { "supabase" => "Supabase" }, runner: serial).fetch

      expect(jobs.map(&:title)).to eq([ "Head of Ecosystem", "AI Platform Engineer" ])
      expect(jobs).to all(have_attributes(remote: true, company: "Supabase", source: "Supabase · Ashby"))
      expect(jobs.first.published_at).to eq(Time.zone.parse("2026-11-10T16:33:17.148+00:00"))
    end
  end
end

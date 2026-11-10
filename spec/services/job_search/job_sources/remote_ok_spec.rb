require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_fetcher")

RSpec.describe JobSearch::JobSources::RemoteOk do
  let(:fetcher) { JobSearch::FakeFetcher.new(described_class::FEED_URL => JobSearch::FakeFetcher.fixture("remote_ok.json")) }

  it "maps the feed, skipping the legal notice in the first item" do
    jobs = described_class.new(fetcher: fetcher).fetch

    expect(jobs.size).to eq(3)
    expect(jobs.first).to have_attributes(
      title: "HIL Support Specialist", company: "Extend Your Team", source: "Remote OK", remote: true,
      location: "Remoto", url: start_with("https://remoteOK.com/remote-jobs/")
    )
    expect(jobs.first.tags).to include("c sharp")
    expect(jobs.first.published_at).to eq(Time.zone.parse("2026-11-09T16:00:20+00:00"))
  end

  it "turns invalid JSON into a source error" do
    fetcher = JobSearch::FakeFetcher.new(described_class::FEED_URL => "<html>")

    expect { described_class.new(fetcher: fetcher).fetch }.to raise_error(JobSearch::JobSourceError, /Remote OK/)
  end
end

require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_fetcher")

RSpec.describe JobSearch::JobSources::Arbeitnow do
  it "maps the jobs with tags, job types and the creation time" do
    fetcher = JobSearch::FakeFetcher.new(described_class::FEED_URL => JobSearch::FakeFetcher.fixture("arbeitnow.json"))

    job = described_class.new(fetcher: fetcher).fetch.first

    expect(job).to have_attributes(
      title: "Werkstudent (m/f/d) Product Management Orthodontics", company: "GC Orthodontics Europe GmbH",
      location: "Breckerfeld", remote: false, source: "Arbeitnow", published_at: Time.zone.at(1_794_344_436)
    )
    expect(job.tags).to include("Product Management", "Werkstudent")
  end
end

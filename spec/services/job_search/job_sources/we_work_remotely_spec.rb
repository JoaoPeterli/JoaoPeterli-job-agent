require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_fetcher")

RSpec.describe JobSearch::JobSources::WeWorkRemotely do
  let(:url) { "https://weworkremotely.com/categories/remote-back-end-programming-jobs.rss" }
  let(:fetcher) { JobSearch::FakeFetcher.new(url => JobSearch::FakeFetcher.fixture("we_work_remotely.rss")) }

  it "splits 'Company: Role' titles and reads region, skills and date" do
    job = described_class.new(fetcher: fetcher, feed_urls: [ url ]).fetch.second

    expect(job).to have_attributes(
      title: "AI Data Quality Analyst", company: "EdgeQ Technologies Private Limited",
      location: "USA Only", remote: true, source: "We Work Remotely",
      url: start_with("https://weworkremotely.com/remote-jobs/"),
      published_at: Time.zone.parse("Tue, 10 Nov 2026 17:00:36 +0000")
    )
    expect(job.tags).to include("Python", "SQL", "Data Annotation")
  end

  it "reads every configured category feed" do
    other = "https://weworkremotely.com/categories/remote-devops-sysadmin-jobs.rss"
    fetcher = JobSearch::FakeFetcher.new(url => JobSearch::FakeFetcher.fixture("we_work_remotely.rss"),
                                         other => JobSearch::FakeFetcher.fixture("we_work_remotely.rss"))

    expect(described_class.new(fetcher: fetcher, feed_urls: [ url, other ]).fetch.size).to eq(6)
  end

  it "turns a broken feed into a source error" do
    fetcher = JobSearch::FakeFetcher.new(url => "<rss><item>")

    expect { described_class.new(fetcher: fetcher, feed_urls: [ url ]).fetch }
      .to raise_error(JobSearch::JobSourceError, /We Work Remotely/)
  end
end

require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_fetcher")

RSpec.describe "Keyword sources (Jobicy, Himalayas, Jooble)" do
  let(:fixture) { ->(name) { JobSearch::FakeFetcher.fixture(name) } }

  describe JobSearch::JobSources::Jobicy do
    let(:url) { "https://jobicy.com/api/v2/remote-jobs?count=50&tag=ruby+on+rails" }

    it "searches by tag, caching each tag for one hour as Jobicy asks" do
      fetcher = JobSearch::FakeFetcher.new(url => fixture.("jobicy.json"))

      job = described_class.new(fetcher: fetcher).search(technology: "Ruby on Rails", remote: true).first

      expect(job).to have_attributes(title: "Sr. Software Engineer, Ruby on Rails", company: "CentralReach",
                                     source: "Jobicy", location: "USA", remote: true,
                                     published_at: Time.zone.parse("2026-11-10T03:05:20+00:00"))
      expect(job.tags).to include("Software Engineering", "Senior")
      expect(fetcher.requests.last[:ttl]).to eq(1.hour)
    end

    it "turns an unexpected payload into a source error" do
      fetcher = JobSearch::FakeFetcher.new(url => '{"success":false}')

      expect { described_class.new(fetcher: fetcher).search(technology: "Ruby on Rails", remote: true) }
        .to raise_error(JobSearch::JobSourceError, /Jobicy: unexpected response/)
    end
  end

  describe JobSearch::JobSources::Himalayas do
    it "searches by keyword and shortens long country lists" do
      url = "https://himalayas.app/jobs/api/search?limit=20&q=React"
      fetcher = JobSearch::FakeFetcher.new(url => fixture.("himalayas.json"))

      job = described_class.new(fetcher: fetcher).search(technology: "React", remote: true).first

      expect(job).to have_attributes(title: "Senior React Native Developer", company: "lemon.io", source: "Himalayas",
                                     remote: true, location: "Albania, Andorra, Argentina +70",
                                     url: start_with("https://himalayas.app/companies/lemon-io/jobs/"),
                                     published_at: Time.zone.at(1_792_087_770))
      expect(job.tags).to include("React Native Developer", "Senior")
    end
  end

  describe JobSearch::JobSources::Jooble do
    let(:url) { "https://jooble.org/api/s3cr3t" }

    def search(fetcher, remote:)
      described_class.new(fetcher: fetcher, api_key: "s3cr3t", location: "Brazil").search(technology: "Ruby", remote: remote)
    end

    it "posts the search (remote uses the 'Remote' location) and keeps the key out of the cache key" do
      fetcher = JobSearch::FakeFetcher.new(url => fixture.("jooble.json"))

      first, second = search(fetcher, remote: true)

      request = fetcher.requests.last
      expect(request[:body]).to eq(keywords: "Ruby", location: "Remote")
      expect(request[:cache_key]).not_to include("s3cr3t")
      expect(request[:ttl]).to eq(6.hours)
      expect(first).to have_attributes(title: "Staff Ruby Engineer", company: "AuraOne Human Data",
                                       source: "auraone.ai via Jooble", location: "Remote", remote: true,
                                       url: start_with("https://jooble.org/desc/"),
                                       published_at: Time.zone.parse("2026-10-07T10:07:57.6726405+00:00"))
      expect(second).to have_attributes(location: "San Francisco, CA", remote: false, tags: [ "Temporary" ])
    end

    it "uses the configured location (in English) for on-site searches" do
      fetcher = JobSearch::FakeFetcher.new(url => fixture.("jooble.json"))

      search(fetcher, remote: false)

      expect(fetcher.requests.last[:body]).to eq(keywords: "Ruby", location: "Brazil")
    end

    it "drops paid studies and panels that are not jobs, and trusts only the location for remote" do
      jobs = [
        { "title" => "Paid Focus Group Participant - Remote Research - Ruby", "location" => "Ruby, NY", "link" => "https://jooble.org/desc/1" },
        { "title" => "Paid Research Panelist - Remote Participation - Ruby", "location" => "Ruby, AK", "link" => "https://jooble.org/desc/2" },
        { "title" => "Ruby Developer (Remote friendly)", "location" => "Austin, TX", "link" => "https://jooble.org/desc/3" }
      ]
      fetcher = JobSearch::FakeFetcher.new(url => { totalCount: 3, jobs: jobs }.to_json)

      result = search(fetcher, remote: true)

      expect(result.map(&:title)).to eq([ "Ruby Developer (Remote friendly)" ])
      expect(result.first.remote).to be(false)
    end

    it "requires the key" do
      expect { described_class.new(fetcher: nil, api_key: nil).search(technology: "Ruby", remote: false) }
        .to raise_error(JobSearch::JobSourceError, /JOOBLE_API_KEY/)
    end
  end
end

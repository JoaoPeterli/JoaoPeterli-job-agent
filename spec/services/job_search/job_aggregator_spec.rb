require "rails_helper"

RSpec.describe JobSearch::JobAggregator do
  let(:event_logger) { instance_double(JobSearch::Observability::EventLogger, warn: nil) }

  def job(title, company: "ACME", remote: true, tags: [], hours_ago: 1)
    JobSearch::JobListing.build(title: title, company: company, url: "https://example.com/#{title.parameterize}",
                                source: "Teste", remote: remote, tags: tags, published_at: hours_ago.hours.ago)
  end

  def source_with(*jobs)
    Struct.new(:jobs) { def fetch = jobs }.new(jobs)
  end

  def failing_source
    Class.new { def fetch = raise(JobSearch::JobSourceError, "down") }.new
  end

  def aggregator(*sources, **options)
    described_class.new(sources: sources, event_logger: event_logger, **options)
  end

  it "keeps jobs that mention the technology as a whole word in the title or tags" do
    sources = source_with(job("Senior Ruby Engineer"), job("Backend dev", tags: [ "ruby" ]),
                          job("Rubyist"), job("Java Developer"))

    titles = aggregator(sources).search(technology: "Ruby", remote: false).map(&:title)

    expect(titles).to contain_exactly("Senior Ruby Engineer", "Backend dev")
  end

  it "does not match Java with JavaScript" do
    titles = aggregator(source_with(job("JavaScript Developer"), job("Java Engineer")))
             .search(technology: "Java", remote: false).map(&:title)

    expect(titles).to eq([ "Java Engineer" ])
  end

  it "matches any relevant term of a multi-word technology" do
    titles = aggregator(source_with(job("Rails Engineer"), job("Ruby Dev"), job("Python Dev")))
             .search(technology: "Ruby on Rails", remote: false).map(&:title)

    expect(titles).to contain_exactly("Rails Engineer", "Ruby Dev")
  end

  it "filters remote jobs, removes duplicates across sources and sorts newest first" do
    sources = [
      source_with(job("Ruby Dev", hours_ago: 5), job("Ruby Onsite", remote: false)),
      source_with(job("ruby dev", company: "acme", hours_ago: 2), job("Ruby Lead", hours_ago: 1))
    ]

    titles = aggregator(*sources).search(technology: "Ruby", remote: true).map(&:title)

    expect(titles).to eq([ "Ruby Lead", "Ruby Dev" ])
  end

  it "drops postings older than 60 days but keeps undated ones" do
    undated = JobSearch::JobListing.build(title: "Ruby Undated", url: "https://example.com/u", source: "Teste")
    sources = source_with(job("Ruby New", hours_ago: 24 * 59), job("Ruby Old", hours_ago: 24 * 61), undated)

    titles = aggregator(sources).search(technology: "Ruby", remote: false).map(&:title)

    expect(titles).to eq([ "Ruby New", "Ruby Undated" ])
  end

  it "caps each source so a big one does not fill the list alone" do
    big = Array.new(10) { |i| job("Ruby #{i}", hours_ago: i + 1) }
    small = JobSearch::JobListing.build(title: "Ruby Small", url: "https://example.com/s", source: "Outra",
                                        published_at: 30.hours.ago)

    jobs = aggregator(source_with(*big), source_with(small)).search(technology: "Ruby", remote: false)

    expect(jobs.count { |j| j.source == "Teste" }).to eq(described_class::MAX_PER_SOURCE)
    expect(jobs.map(&:title)).to include("Ruby Small")
  end

  it "limits the number of jobs" do
    jobs = Array.new(5) { |i| job("Ruby #{i}") }

    expect(aggregator(source_with(*jobs), limit: 3).search(technology: "Ruby", remote: false).size).to eq(3)
  end

  it "keeps searching when one source fails and logs the failure" do
    result = aggregator(failing_source, source_with(job("Ruby Dev"))).search(technology: "Ruby", remote: false)

    expect(result.map(&:title)).to eq([ "Ruby Dev" ])
    expect(event_logger).to have_received(:warn)
      .with(hash_including(event: "job_source.failed", error_class: "JobSearch::JobSourceError"))
  end

  it "fails with a transient error only when every source fails" do
    expect { aggregator(failing_source, failing_source).search(technology: "Ruby", remote: false) }
      .to raise_error(JobSearch::JobSourcesUnavailableError) { |error| expect(error).to be_a(JobSearch::TransientError) }
  end

  it "asks sources that search by themselves (the sample source)" do
    result = aggregator(JobSearch::JobSources::Sample.new).search(technology: "Elixir", remote: true)

    expect(result.map(&:to_tool_output)).to eq([
      { title: "Senior Elixir Developer", company: "Example Company", remote: true, url: nil,
        source: "Exemplo", location: nil, published_at: nil, tags: [ "Elixir" ] }
    ])
  end
end

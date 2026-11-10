require "rails_helper"

RSpec.describe JobSearch::JobSources::HttpFetcher do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:fetcher) { described_class.new(cache: cache) }

  def http_response(klass, code, body)
    klass.new("1.1", code, "msg").tap do |response|
      response.instance_variable_set(:@read, true)
      response.instance_variable_set(:@body, body)
    end
  end

  it "fetches once and serves the next calls from the cache" do
    allow(Net::HTTP).to receive(:start).and_return(http_response(Net::HTTPOK, "200", "[]"))

    2.times { expect(fetcher.get("https://example.com/feed")).to eq("[]") }

    expect(Net::HTTP).to have_received(:start).once
      .with("example.com", 443, hash_including(use_ssl: true, open_timeout: 3, read_timeout: 5))
  end

  it "refuses plain http" do
    expect { fetcher.get("http://example.com/feed") }.to raise_error(JobSearch::JobSourceError, /only https/)
  end

  it "turns HTTP errors and network failures into source errors, without caching them" do
    allow(Net::HTTP).to receive(:start).and_return(http_response(Net::HTTPTooManyRequests, "429", ""))
    expect { fetcher.get("https://example.com/feed") }.to raise_error(JobSearch::JobSourceError, /HTTP 429/)

    allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)
    expect { fetcher.get("https://example.com/feed") }.to raise_error(JobSearch::JobSourceError, /unreachable/)
  end

  it "posts JSON caching by the given key, and errors never show the URL path (where keys live)" do
    allow(Net::HTTP).to receive(:start).and_return(http_response(Net::HTTPOK, "200", "{}"))

    2.times { fetcher.post_json("https://example.com/api/s3cr3t", body: { q: "ruby" }, cache_key: "x/q=ruby") }

    expect(Net::HTTP).to have_received(:start).once
    expect(cache.exist?("job_sources/x/q=ruby")).to be(true)

    allow(Net::HTTP).to receive(:start).and_return(http_response(Net::HTTPForbidden, "403", ""))
    expect { fetcher.post_json("https://example.com/api/s3cr3t", body: {}, cache_key: "y") }
      .to raise_error(JobSearch::JobSourceError) { |error| expect(error.message).not_to include("s3cr3t") }
  end
end

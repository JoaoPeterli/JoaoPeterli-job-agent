module JobSearch
  # Fetcher sem rede para os specs das fontes: URL => corpo (ou erro).
  class FakeFetcher
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def get(url, headers: {}, ttl: nil)
      @requests << { url: url, headers: headers, ttl: ttl }
      response = @responses.fetch(url) { raise JobSearch::JobSourceError, "unexpected URL #{url}" }
      raise response if response.is_a?(Exception)

      response
    end

    def post_json(url, body:, cache_key:, ttl: nil)
      @requests << { url: url, body: body, cache_key: cache_key, ttl: ttl }
      response = @responses.fetch(url) { raise JobSearch::JobSourceError, "unexpected URL" }
      raise response if response.is_a?(Exception)

      response
    end

    def self.fixture(name)
      Rails.root.join("spec/fixtures/job_sources", name).read
    end
  end
end

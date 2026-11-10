require "rails_helper"

RSpec.describe JobSearch::SearchJobsTool do
  describe "#call" do
    it "returns the aggregated jobs in the tool output format" do
      published_at = Time.zone.parse("2026-11-10 10:00")
      job = JobSearch::JobListing.build(title: "Ruby Dev", company: "ACME", url: "https://example.com/1",
                                        source: "Remote OK", remote: true, published_at: published_at)
      aggregator = instance_double(JobSearch::JobAggregator, search: [ job ])

      result = described_class.new(aggregator: aggregator).call(technology: "Ruby", remote: true)

      expect(aggregator).to have_received(:search).with(technology: "Ruby", remote: true)
      expect(result).to eq([
        { title: "Ruby Dev", company: "ACME", remote: true, url: "https://example.com/1", source: "Remote OK",
          location: nil, published_at: published_at.iso8601, tags: [] }
      ])
    end

    it "uses the configured sources (only the offline sample in tests)" do
      expect(described_class.new.call(technology: "Ruby", remote: true).first)
        .to include(title: "Senior Ruby Developer", source: "Exemplo")
    end
  end
end

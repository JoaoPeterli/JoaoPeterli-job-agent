require "rails_helper"

RSpec.describe JobSearch::OperationFingerprint do
  describe ".call" do
    it "generates the same fingerprint regardless of hash key order" do
      first = described_class.call(
        tool: "search_jobs",
        arguments: {
          technology: "Ruby",
          remote: true
        }
      )

      second = described_class.call(
        tool: "search_jobs",
        arguments: {
          remote: true,
          technology: "Ruby"
        }
      )

      expect(first).to eq(second)
    end

    it "generates different fingerprints for different operations" do
      first = described_class.call(
        tool: "search_jobs",
        arguments: { technology: "Ruby" }
      )

      second = described_class.call(
        tool: "search_jobs",
        arguments: { technology: "Elixir" }
      )

      expect(first).not_to eq(second)
    end
  end
end

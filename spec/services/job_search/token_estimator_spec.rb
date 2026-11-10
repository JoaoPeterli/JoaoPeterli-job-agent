require "rails_helper"

RSpec.describe JobSearch::TokenEstimator do
  subject(:estimator) { described_class.new }

  describe "#count" do
    it "estimates about four characters per token, rounding up" do
      expect(estimator.count("")).to eq(0)
      expect(estimator.count("abcd")).to eq(1)
      expect(estimator.count("abcde")).to eq(2)
    end

    it "treats nil as empty" do
      expect(estimator.count(nil)).to eq(0)
    end
  end

  describe "#truncate" do
    it "keeps text that already fits" do
      expect(estimator.truncate("short", max_tokens: 10)).to eq("short")
    end

    it "cuts long text and marks it as truncated within the limit" do
      result = estimator.truncate("x" * 1_000, max_tokens: 20)

      expect(result).to end_with("...[truncated]")
      expect(estimator.count(result)).to be <= 20
    end

    it "returns an empty string when not even the marker fits" do
      expect(estimator.truncate("x" * 100, max_tokens: 1)).to eq("")
    end
  end
end

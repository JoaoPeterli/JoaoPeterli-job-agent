
require "rails_helper"

RSpec.describe JobSearch::ReconciliationBackoff do
  subject(:backoff) do
    described_class.new(
      base_delay: 30,
      max_delay: 300
    )
  end

  describe "#delay_for" do
    it "returns 30 seconds for the first attempt" do
      expect(backoff.delay_for(1)).to eq(30)
    end

    it "doubles the delay for each attempt" do
      expect(backoff.delay_for(2)).to eq(60)
      expect(backoff.delay_for(3)).to eq(120)
      expect(backoff.delay_for(4)).to eq(240)
    end

    it "respects the maximum delay" do
      expect(backoff.delay_for(5)).to eq(300)
      expect(backoff.delay_for(10)).to eq(300)
    end

    it "rejects invalid attempt numbers" do
      expect do
        backoff.delay_for(0)
      end.to raise_error(ArgumentError)

      expect do
        backoff.delay_for(-1)
      end.to raise_error(ArgumentError)
    end
  end
end

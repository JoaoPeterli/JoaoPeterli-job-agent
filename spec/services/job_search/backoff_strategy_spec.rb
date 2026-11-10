require "rails_helper"

RSpec.describe JobSearch::BackoffStrategy do
  describe "#delay_for" do
    it "calculates exponential backoff" do
      strategy = described_class.new(
        base_delay: 1
      )

      expect(strategy.delay_for(1)).to eq(1)
      expect(strategy.delay_for(2)).to eq(2)
      expect(strategy.delay_for(3)).to eq(4)
      expect(strategy.delay_for(4)).to eq(8)
    end
  end
end

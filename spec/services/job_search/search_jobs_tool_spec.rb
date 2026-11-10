require "rails_helper"

RSpec.describe JobSearch::SearchJobsTool do
  describe "#call" do
    it "returns jobs matching the search" do
      tool = described_class.new

      result = tool.call(
        technology: "Ruby",
        remote: true
      )

      expect(result).to be_an(Array)
      expect(result).not_to be_empty
    end
  end
end

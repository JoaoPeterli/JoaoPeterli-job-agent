require "rails_helper"

RSpec.describe JobSearch::CandidateProfileTool do
  describe "#call" do
    it "returns the candidate profile" do
      result = described_class.new.call

      expect(result).to eq(
        {
          skills: [
            "Ruby",
            "Rails",
            "AWS"
          ],
          seniority: "Senior",
          remote: true
        }
      )
    end
  end
end

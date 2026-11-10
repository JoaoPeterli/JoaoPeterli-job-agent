require "rails_helper"

RSpec.describe JobSearch::AnalyzeJobsTool do
  describe "#call" do
    it "scores jobs against the candidate profile" do
      jobs = [
        {
          title: "Senior Ruby Developer",
          company: "Example Company",
          remote: true
        }
      ]

      profile = {
        skills: [
          "Ruby",
          "Rails",
          "AWS"
        ],
        seniority: "Senior",
        remote: true
      }

      result = described_class.new.call(
        jobs: jobs,
        profile: profile
      )

      expect(result).to eq(
        [
          {
            title: "Senior Ruby Developer",
            company: "Example Company",
            remote: true,
            score: 40
          }
        ]
      )
    end
  end
end

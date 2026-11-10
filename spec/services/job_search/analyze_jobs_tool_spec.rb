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

    it "finds skills in the tags too, ignoring case, as whole words" do
      profile = { skills: %w[Ruby Rails AWS], remote: false }
      jobs = [
        { title: "Backend engineer (ruby)", tags: [ "rails", "Postgres" ], remote: true },
        { title: "Rubyist wanted", tags: [ "awsome" ], remote: true }
      ]

      scores = described_class.new.call(jobs: jobs, profile: profile).map { |job| job[:score] }

      expect(scores).to eq([ 40, 0 ])
    end
  end
end

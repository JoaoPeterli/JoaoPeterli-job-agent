require "rails_helper"

RSpec.describe JobSearch::CandidateProfileTool do
  describe "#call" do
    it "returns the default profile while none is saved" do
      expect(described_class.new.call).to eq(skills: %w[Ruby Rails AWS], seniority: "senior", remote: true, location: nil)
    end

    it "returns the profile saved in 'Meu perfil'" do
      CandidateProfile.create!(skills: %w[Elixir Phoenix], seniority: "pleno", remote: false, location: "Recife")

      expect(described_class.new.call).to eq(skills: %w[Elixir Phoenix], seniority: "pleno", remote: false, location: "Recife")
    end

    it "adds the preference memory once the user marked jobs" do
      JobFeedback.toggle!({ "title" => "Rails Dev", "company" => "ACME", "remote" => true }, verdict: "like")

      expect(described_class.new.call[:preferences]).to eq(
        liked: [ { title: "Rails Dev", company: "ACME", location: nil, remote: true, tags: [] } ], disliked: []
      )
    end
  end
end

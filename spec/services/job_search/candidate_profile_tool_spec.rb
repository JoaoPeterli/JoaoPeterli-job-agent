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
  end
end

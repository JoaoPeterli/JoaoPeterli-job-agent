require "rails_helper"

RSpec.describe CandidateProfile do
  it "is the default (unsaved) profile until one is saved" do
    profile = described_class.current

    expect(profile).to be_new_record
    expect(profile.to_tool_output).to eq(skills: %w[Ruby Rails AWS], seniority: "senior", remote: true, location: nil)
  end

  it "parses skills from the form text, dropping blanks and case-insensitive duplicates" do
    profile = described_class.new(skills_text: " Ruby, rails;Rails\n, ,AWS ", seniority: "senior")

    expect(profile).to be_valid
    expect(profile.skills).to eq(%w[Ruby rails AWS])
    expect(profile.skills_text).to eq("Ruby, rails, AWS")
  end

  it "validates skills and seniority" do
    expect(described_class.new(skills: [], seniority: "senior")).not_to be_valid
    expect(described_class.new(skills: [ "x" * 41 ], seniority: "senior")).not_to be_valid
    expect(described_class.new(skills: Array.new(21) { |i| "s#{i}" }, seniority: "senior")).not_to be_valid
    expect(described_class.new(skills: [ "Ruby" ], seniority: "ceo")).not_to be_valid
  end
end

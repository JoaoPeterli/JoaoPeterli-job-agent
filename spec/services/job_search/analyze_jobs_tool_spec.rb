require "rails_helper"

RSpec.describe JobSearch::AnalyzeJobsTool do
  let(:profile) { { skills: %w[Ruby Rails AWS], seniority: "senior", remote: true, location: nil } }

  def score(job, profile: self.profile)
    described_class.new.call(jobs: [ job ], profile: profile).first[:score]
  end

  it "adds the score to each job, keeping its fields" do
    job = { title: "Senior Ruby Developer", company: "Example Company", remote: true }

    expect(described_class.new.call(jobs: [ job ], profile: profile))
      .to eq([ job.merge(score: 60) ]) # Ruby 20 + Sênior 20 + remota 20
  end

  it "finds skills in the tags too, ignoring case, as whole words, up to 60 points" do
    expect(score({ title: "Backend engineer (ruby)", tags: [ "rails", "Postgres" ], remote: false })).to eq(40 + 10)
    expect(score({ title: "Rubyist wanted", tags: [ "awsome" ], remote: false })).to eq(10)

    many = profile.merge(skills: %w[Ruby Rails AWS Postgres Redis])
    expect(score({ title: "Ruby Rails AWS Postgres Redis", remote: false }, profile: many)).to eq(60 + 10)
  end

  it "rewards the same seniority, is neutral when unstated and gives nothing for another level" do
    expect(score({ title: "Sênior Ruby", remote: false })).to eq(20 + 20)
    expect(score({ title: "Sr. Ruby Engineer", remote: false })).to eq(20 + 20)
    expect(score({ title: "Ruby Engineer", remote: false })).to eq(20 + 10)
    expect(score({ title: "Desenvolvedor Ruby Júnior", remote: false })).to eq(20 + 0)
    expect(score({ title: "Staff Ruby Engineer", remote: false }, profile: profile.merge(seniority: "especialista"))).to eq(40)
  end

  it "scores the workplace by the remote preference and the city" do
    onsite = profile.merge(remote: false, location: "São Paulo")

    expect(score({ title: "Ruby", remote: true })).to eq(20 + 10 + 20)
    expect(score({ title: "Ruby", remote: false, location: "São Paulo, SP" })).to eq(20 + 10)
    expect(score({ title: "Ruby", remote: false, location: "São Paulo, SP" }, profile: onsite)).to eq(20 + 10 + 20)
    expect(score({ title: "Ruby", remote: false, location: "Recife" }, profile: onsite)).to eq(20 + 10)
  end

  it "accepts string keys and capitalized seniority (older stored profiles)" do
    expect(score({ title: "Senior Ruby", remote: true }, profile: { "skills" => [ "Ruby" ], "seniority" => "Sênior", "remote" => true }))
      .to eq(60)
  end
end

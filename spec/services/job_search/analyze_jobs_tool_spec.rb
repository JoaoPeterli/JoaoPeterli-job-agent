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

  describe "with the LLM evaluator" do
    let(:event_logger) { instance_double(JobSearch::Observability::EventLogger, warn: nil) }
    let(:evaluator) { instance_double(JobSearch::JobEvaluator, max_jobs: 2) }
    let(:jobs) do
      [
        { title: "Java Developer", remote: false },          # régua: 0 + 10 + 0 = 10
        { title: "Senior Ruby Developer", remote: true },    # régua: 60
        { title: "Rails Engineer", remote: true }            # régua: 20 + 10 + 20 = 50
      ]
    end

    def tool = described_class.new(evaluator: evaluator, event_logger: event_logger)

    it "sends the best jobs by the rules to the LLM and uses its score and reason" do
      allow(evaluator).to receive(:evaluate).and_return(
        0 => JobSearch::JobEvaluator::Evaluation.new(score: 95, reason: "Ruby sênior remoto."),
        1 => JobSearch::JobEvaluator::Evaluation.new(score: 70, reason: "Rails, sem nível definido.")
      )

      result = tool.call(jobs: jobs, profile: profile)

      expect(evaluator).to have_received(:evaluate).with(jobs: [ hash_including(title: "Senior Ruby Developer"),
                                                                  hash_including(title: "Rails Engineer") ],
                                                         profile: profile)
      expect(result.map { |job| job.slice(:title, :score, :scored_by) }).to eq([
        { title: "Java Developer", score: 10, scored_by: "rules" },
        { title: "Senior Ruby Developer", score: 95, scored_by: "llm" },
        { title: "Rails Engineer", score: 70, scored_by: "llm" }
      ])
      expect(result[1]).to include(score_reason: "Ruby sênior remoto.", rule_score: 60)
    end

    it "keeps the rule score for jobs the LLM did not evaluate" do
      allow(evaluator).to receive(:evaluate).and_return(0 => JobSearch::JobEvaluator::Evaluation.new(score: 90, reason: "ok"))

      expect(tool.call(jobs: jobs, profile: profile).last).to include(score: 50, scored_by: "rules")
    end

    it "gives up on a slow LLM before the tool timeout and keeps the rule scores" do
      allow(evaluator).to receive(:evaluate) { sleep 1 }
      slow_tool = described_class.new(evaluator: evaluator, event_logger: event_logger, evaluation_timeout: 0.05)

      expect(slow_tool.call(jobs: jobs, profile: profile).map { |job| job[:scored_by] }).to all(eq("rules"))
      expect(event_logger).to have_received(:warn).with(hash_including(error: "LLM evaluation timed out"))
    end

    it "falls back to the rules (and logs) when the LLM fails, never failing the run" do
      [ JobSearch::JobEvaluationError.new("bad json"),
        JobSearch::LlmBudgetExceeded.new("budget"),
        JobSearch::LlmProviderError.new("down", transient: true) ].each do |error|
        allow(evaluator).to receive(:evaluate).and_raise(error)

        expect(tool.call(jobs: jobs, profile: profile).map { |job| job[:score] }).to eq([ 10, 60, 50 ])
      end

      expect(event_logger).to have_received(:warn).with(hash_including(event: "job_evaluation.failed")).exactly(3).times
    end
  end
end

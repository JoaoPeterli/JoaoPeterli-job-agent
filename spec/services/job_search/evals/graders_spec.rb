require "rails_helper"

RSpec.describe "Eval graders" do
  def eval_case(expect = {})
    JobSearch::Evals::EvalCase.new(id: "c", objective: "Vagas Ruby", expect: expect)
  end

  def search(technology, remote = true)
    { agent: "a", tool: :search_jobs, arguments: { technology: technology, remote: remote } }
  end

  def run(status: :completed, trajectory: [], output: [], metrics: {}, error_class: nil)
    JobSearch::Evals::EvalRun.new(status: status, trajectory: trajectory, output: output, metrics: metrics,
                                  error_class: error_class)
  end

  def by_name(checks) = checks.to_h { |check| [ check.name, check ] }

  describe JobSearch::Evals::Graders::OutcomeGrader do
    let(:grader) { described_class.new }

    it "expects a completed run by default" do
      expect(grader.grade(eval_case, run).first).to be_passed
      expect(grader.grade(eval_case, run(status: :stopped_early)).first.detail).to eq("expected completed, got stopped_early")
    end

    it "expects a rejection with the right error for safety cases" do
      safety = eval_case(outcome: "rejected", error: "UntrustedInputError")

      expect(grader.grade(safety, run(status: :failed, error_class: "JobSearch::UntrustedInputError")).first).to be_passed
      expect(grader.grade(safety, run).first.detail).to eq("expected rejection, got completed")
      expect(grader.grade(safety, run(status: :failed, error_class: "JobSearch::LlmProviderError")).first.detail)
        .to eq("rejected with JobSearch::LlmProviderError, expected UntrustedInputError")
    end
  end

  describe JobSearch::Evals::Graders::ToolUseGrader do
    let(:grader) { described_class.new }

    it "gives partial credit for the technologies covered" do
      checks = by_name(grader.grade(eval_case(technologies: %w[Ruby Rails]), run(trajectory: [ search("Ruby on Rails") ])))

      expect(checks["technologies"]).to be_passed

      checks = by_name(grader.grade(eval_case(technologies: %w[Ruby Go]), run(trajectory: [ search("Ruby") ])))
      expect(checks["technologies"]).to have_attributes(passed: false, score: 0.5, detail: "missing Go (searched: Ruby)")
    end

    it "matches whole words only" do
      checks = by_name(grader.grade(eval_case(technologies: %w[Go]), run(trajectory: [ search("Google Cloud") ])))

      expect(checks["technologies"]).not_to be_passed
    end

    it "checks the remote filter of every search" do
      checks = by_name(grader.grade(eval_case(remote: true), run(trajectory: [ search("Ruby"), search("Rails", false) ])))

      expect(checks["remote"]).to have_attributes(passed: false, score: 0.5, detail: "1/2 searches used remote=false")
    end

    it "flags repeated tool calls" do
      checks = by_name(grader.grade(eval_case, run(trajectory: [ search("Ruby"), search("Ruby") ])))

      expect(checks["no_redundant_calls"].detail).to eq("1 repeated tool call(s)")
    end

    it "does not grade the trajectory of a failed run" do
      expect(grader.grade(eval_case(technologies: %w[Ruby]), run(status: :failed))).to be_empty
    end
  end

  describe JobSearch::Evals::Graders::ResultGrader do
    let(:grader) { described_class.new }
    let(:jobs) { [ { title: "Senior Ruby Developer" }, { title: "Java Developer" } ] }

    it "checks the number of results and their relevance" do
      checks = by_name(grader.grade(eval_case(min_results: 3, technologies: %w[Ruby]), run(output: jobs)))

      expect(checks["min_results"].detail).to eq("2 jobs, expected at least 3")
      expect(checks["result_relevance"]).to have_attributes(passed: false, score: 0.5, detail: "1/2 jobs mention Ruby")
    end

    it "fails relevance when there is nothing to evaluate" do
      checks = by_name(grader.grade(eval_case(technologies: %w[Ruby]), run(output: [])))

      expect(checks["result_relevance"].detail).to eq("no jobs to evaluate")
    end
  end

  describe JobSearch::Evals::Graders::EfficiencyGrader do
    let(:grader) { described_class.new }

    it "checks calls, latency and cost against the limits" do
      checks = by_name(grader.grade(
        eval_case(max_llm_calls: 1, max_duration_ms: 1_000, max_cost_usd: 0.01),
        run(metrics: { "llm_calls" => 2, "duration_ms" => 500.0, "cost_usd" => 0.002 })
      ))

      expect(checks["llm_calls"].detail).to eq("2 > 1")
      expect(checks["duration_ms"]).to be_passed
      expect(checks["cost_usd"]).to be_passed
    end

    it "does not fail when the cost is unknown" do
      check = grader.grade(eval_case(max_cost_usd: 0.01), run(metrics: { "cost_usd" => nil })).first

      expect(check).to have_attributes(passed: true, detail: "cost unknown (no pricing configured)")
    end
  end
end

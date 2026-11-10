require "rails_helper"

RSpec.describe JobSearch::Evals::Report do
  def result(id, passed:, duration: 100.0, cost: 0.001, calls: 1)
    check = passed ? JobSearch::Evals::Check.pass(:outcome) : JobSearch::Evals::Check.fail(:outcome, "bad")
    run = JobSearch::Evals::EvalRun.new(
      status: :completed, metrics: { "duration_ms" => duration, "cost_usd" => cost, "llm_calls" => calls }
    )
    JobSearch::Evals::CaseResult.new(case_id: id, tags: [], run: run, checks: [ check ])
  end

  def report(*results) = described_class.new(dataset_name: "d", target: :agent, results: results)

  it "aggregates pass rate, scores, calls and cost" do
    summary = report(result("a", passed: true), result("b", passed: false, cost: 0.002)).summary

    expect(summary).to include(cases: 2, passed: 1, pass_rate: 0.5, mean_score: 0.5, llm_calls: 2, cost_usd: 0.003)
    expect(summary[:checks]).to eq("outcome" => { passed: 1, total: 2, pass_rate: 0.5 })
  end

  it "computes nearest-rank latency percentiles" do
    durations = [ 10, 20, 30, 40, 50, 60, 70, 80, 90, 1_000 ]
    latency = report(*durations.map.with_index { |d, i| result("c#{i}", passed: true, duration: d) }).summary[:latency_ms]

    expect(latency).to eq(p50: 50, p95: 1_000)
  end

  it "reports the total cost as unknown when any case has no cost" do
    expect(report(result("a", passed: true), result("b", passed: true, cost: nil)).summary[:cost_usd]).to be_nil
  end

  describe "#regressions" do
    let(:baseline) { report(result("a", passed: true), result("b", passed: true)).to_h }

    it "is empty when nothing got worse" do
      expect(report(result("a", passed: true), result("b", passed: true)).regressions(baseline)).to be_empty
    end

    it "lists the drop in pass rate and every case that stopped passing" do
      current = report(result("a", passed: true), result("b", passed: false))

      expect(current.regressions(baseline)).to eq([
        "pass rate dropped from 1.0 to 0.5", "case b regressed: outcome"
      ])
    end

    it "tolerates small drops in pass rate, but never a case regression" do
      current = report(result("a", passed: true), result("b", passed: false))

      expect(current.regressions(baseline, tolerance: 0.5)).to eq([ "case b regressed: outcome" ])
    end

    it "does not count a case that was already failing" do
      failing_baseline = report(result("a", passed: true), result("b", passed: false)).to_h

      expect(report(result("a", passed: true), result("b", passed: false)).regressions(failing_baseline)).to be_empty
    end
  end

  it "renders a readable summary" do
    text = report(result("a", passed: true), result("b", passed: false)).to_text

    expect(text).to include("1/2 passed")
    expect(text).to include("FAIL b")
    expect(text).to include("- outcome: bad")
  end
end

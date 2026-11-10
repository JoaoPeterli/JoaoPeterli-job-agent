require "rails_helper"
require Rails.root.join("spec/support/job_search/eval_cassettes")

# Eval de qualidade OFFLINE: o dataset versionado (evals/job_search.yml)
# roda no sistema real com respostas de LLM gravadas. Serve de gate no CI:
# uma mudança de prompt, validador ou ferramenta que piore a qualidade
# reprova aqui, sem gastar tokens.
RSpec.describe "Job search quality eval (offline)" do
  let(:dataset) { JobSearch::Evals::Dataset.load(Rails.root.join("evals/job_search.yml")) }

  def run_eval(target: :agent, overrides: {})
    JobSearch::Evals::Runner.new(
      target: target,
      container_factory: JobSearch::EvalCassettes.container_factory(target, overrides: overrides)
    ).run(dataset)
  end

  it "passes every case of the dataset" do
    report = run_eval

    expect(report.passed?).to be(true), report.to_text
    expect(report.summary).to include(cases: 5, passed: 5, pass_rate: 1.0)
  end

  it "covers safety: the injection case is rejected before any LLM call" do
    result = run_eval.results.find { |item| item.case_id == "injection_in_objective" }

    expect(result.run).to have_attributes(status: :failed, error_class: "JobSearch::UntrustedInputError")
    expect(result.checks.map(&:name)).to eq(%w[outcome llm_calls])
    expect(result.passed?).to be(true)
  end

  it "aggregates quality, cost and latency" do
    summary = run_eval.summary

    expect(summary[:checks]).to include("technologies" => { passed: 4, total: 4, pass_rate: 1.0 })
    expect(summary[:llm_calls]).to eq(4)
    expect(summary[:latency_ms]).to include(:p50, :p95)
    expect(summary[:cost_usd]).to be_nil # sem preço configurado em config/llm_pricing.yml
  end

  context "when a change degrades the plans" do
    # Simula uma regressão: o planner passa a buscar só Ruby no caso
    # Ruby + Rails, e esquece o filtro remoto.
    let(:degraded) do
      {
        "ruby_and_rails" => {
          "execution planner" => [ { steps: [
            { name: "ruby", tool: "search_jobs", arguments: { technology: "Ruby", remote: false }, dependencies: [] }
          ] } ]
        }
      }
    end

    it "explains which checks failed, with partial credit" do
      result = run_eval(overrides: degraded).results.find { |item| item.case_id == "ruby_and_rails" }

      failed = result.failed_checks.to_h { |check| [ check.name, check.detail ] }
      expect(failed.keys).to eq(%w[technologies remote min_results])
      expect(failed["technologies"]).to eq("missing Rails (searched: Ruby)")
      expect(result.checks.find { |check| check.name == "technologies" }.score).to eq(0.5)
    end

    it "is caught as a regression against the baseline" do
      baseline = run_eval.to_h

      regressions = run_eval(overrides: degraded).regressions(baseline)

      expect(regressions).to eq([
        "pass rate dropped from 1.0 to 0.8",
        "case ruby_and_rails regressed: technologies, remote, min_results"
      ])
    end
  end

  # Achado do próprio eval: o time entrega a mesma qualidade, mas gasta 4
  # chamadas de LLM (supervisor + 3 especialistas) onde o agente único
  # gasta 1. O orçamento do dataset (3) reprova o time só por custo.
  it "shows the supervisor team matches the quality but costs more LLM calls" do
    overrides = {
      "ruby_and_rails" => {
        "coordinator of a job search team" => [ { delegations: [
          { id: "ruby", agent: "researcher", task: "Search remote Ruby jobs", inputs: [] },
          { id: "rails", agent: "researcher", task: "Search remote Rails jobs", inputs: [] },
          { id: "rank", agent: "analyst", task: "Score the jobs for the candidate", inputs: %w[ruby rails] }
        ] } ],
        "Search remote Ruby jobs" => [ { steps: [
          { name: "s", tool: "search_jobs", arguments: { technology: "Ruby", remote: true }, dependencies: [] }
        ] } ],
        "Search remote Rails jobs" => [ { steps: [
          { name: "s", tool: "search_jobs", arguments: { technology: "Rails", remote: true }, dependencies: [] }
        ] } ],
        "Score the jobs" => [ { steps: [
          { name: "profile", tool: "candidate_profile", arguments: {}, dependencies: [] },
          { name: "analyze", tool: "analyze_jobs",
            arguments: { jobs: { "$ref": "jobs" }, profile: { "$ref": "profile" } }, dependencies: [ "profile" ] }
        ] } ]
      }
    }
    single = JobSearch::Evals::Dataset.new(name: "team", cases: [ dataset.cases.find { |item| item.id == "ruby_and_rails" } ])

    report = JobSearch::Evals::Runner.new(
      target: :supervisor,
      container_factory: JobSearch::EvalCassettes.container_factory(:supervisor, overrides: overrides)
    ).run(single)

    result = report.results.first
    expect(result.failed_checks.map { |check| [ check.name, check.detail ] }).to eq([ [ "llm_calls", "4 > 3" ] ])
    expect(result.checks.reject { |check| check.name == "llm_calls" }).to all(be_passed)
    expect(result.run.trajectory.map { |call| [ call[:agent], call[:tool] ] }).to eq([
      [ "ruby", :search_jobs ], [ "rails", :search_jobs ], [ "rank", :candidate_profile ], [ "rank", :analyze_jobs ]
    ])
    expect(result.run.metrics["llm_calls"]).to eq(4)
  end
end

require "rails_helper"
require Rails.root.join("spec/support/job_search/scripted_llm_client")
require Rails.root.join("spec/support/job_search/captured_events")

RSpec.describe "Agent metrics, cost and latency" do
  let(:events) { JobSearch::CapturedEvents.new }
  let(:objective) { "Encontrar vagas Ruby remotas" }

  def fixture(name)
    File.read(Rails.root.join("spec/fixtures/llm/plans", name))
  end

  def response(name, input:, output:, cached: 0)
    JobSearch::LlmResponse.new(
      text: fixture(name),
      model: "gpt-5.6-2026-08-01",
      usage: JobSearch::LlmUsage.new(input_tokens: input, output_tokens: output, cached_input_tokens: cached)
    )
  end

  def run_agent(responses)
    llm_client = JobSearch::ScriptedLlmClient.new(responses)
    agent = JobSearch::Container.new(llm_client: llm_client, event_logger: events.event_logger)
                                .agent(objective: objective)
    [ agent, llm_client ]
  end

  def run_metrics
    events.all.select { |event| event["event"] == "run.metrics" }
  end

  context "with prices configured" do
    before do
      table = JobSearch::LlmPricingTable.new(
        "gpt-5.6" => JobSearch::LlmPricing.new(
          input_per_million: 2.0, cached_input_per_million: 0.5, output_per_million: 8.0
        )
      )
      allow(JobSearch::LlmPricingTable).to receive(:load).and_return(table)
    end

    it "emits one run.metrics event with real tokens, cost and latency" do
      agent, = run_agent([
        response("unknown_tool.json", input: 1_000, output: 200),
        response("valid_full_plan.json", input: 1_200, output: 300, cached: 1_000)
      ])

      state = agent.run

      expect(run_metrics.size).to eq(1)
      metrics = run_metrics.first

      # 1ª: 1000*2 + 200*8 = 3600 | 2ª: 200*2 + 1000*0.5 + 300*8 = 3300 -> 6900 / 1M
      expect(metrics).to include(
        "trace_id" => state.run_id, "run_status" => "completed",
        "planning_attempts" => 2, "llm_calls" => 2,
        "input_tokens" => 2_200, "cached_input_tokens" => 1_000, "output_tokens" => 500, "total_tokens" => 2_700,
        "cost_usd" => 0.0069, "cost_complete" => true, "usage_missing_calls" => 0,
        "tool_calls" => 3, "failed_tool_calls" => 0
      )
      expect(metrics["llm_latency_ms"]).to be <= metrics["duration_ms"]
      expect(metrics["llm_latency_max_ms"]).to be <= metrics["llm_latency_ms"]
    end

    it "stops planning when the run's LLM budget is spent" do
      stub_const("JobSearch::Container::MAX_LLM_TOKENS_PER_RUN", 1_000)
      agent, llm_client = run_agent([
        response("unknown_tool.json", input: 900, output: 200),
        response("valid_full_plan.json", input: 900, output: 200)
      ])

      expect { agent.run }.to raise_error(JobSearch::LlmBudgetExceeded)
      expect(llm_client.calls).to eq(1)
      expect(run_metrics.first).to include("run_status" => "failed", "llm_calls" => 1, "total_tokens" => 1_100)
    end
  end

  it "reports the cost as unknown when the model has no price" do
    allow(JobSearch::LlmPricingTable).to receive(:load).and_return(JobSearch::LlmPricingTable.new)
    agent, = run_agent([ response("valid_full_plan.json", input: 500, output: 100) ])

    agent.run

    expect(run_metrics.first).to include("cost_usd" => nil, "cost_complete" => false, "total_tokens" => 600)
  end

  it "emits metrics for a run that fails before planning succeeds" do
    agent, = run_agent([ JobSearch::LlmResponse.new(text: "", refusal: "No.") ])

    expect { agent.run }.to raise_error(JobSearch::LlmRefusalError)
    expect(run_metrics.first).to include("run_status" => "failed", "llm_calls" => 1, "tool_calls" => 0)
  end

  it "keeps the objective and the prompt out of the metrics" do
    agent, = run_agent([ response("valid_full_plan.json", input: 10, output: 10) ])

    agent.run

    expect(events.raw).not_to include(objective)
    expect(events.raw).not_to include("Available tools")
  end
end

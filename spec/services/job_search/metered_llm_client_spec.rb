require "rails_helper"
require Rails.root.join("spec/support/job_search/scripted_llm_client")
require Rails.root.join("spec/support/job_search/captured_events")

RSpec.describe JobSearch::MeteredLlmClient do
  let(:events) { JobSearch::CapturedEvents.new }
  let(:tracer) { JobSearch::Observability::Tracer.new(event_logger: events.event_logger) }
  let(:pricing_table) do
    JobSearch::LlmPricingTable.new(
      "gpt-x" => JobSearch::LlmPricing.new(input_per_million: 1.0, output_per_million: 4.0)
    )
  end
  let(:budget) { JobSearch::LlmBudget.new(max_total_tokens: 1_000) }

  def usage(input, output)
    JobSearch::LlmUsage.new(input_tokens: input, output_tokens: output)
  end

  def metered(responses, model: "gpt-x")
    inner = JobSearch::ScriptedLlmClient.new(responses)
    client = described_class.new(
      client: inner, tracer: tracer, pricing_table: pricing_table, budget: budget, model: model
    )
    [ client, inner ]
  end

  def call_span
    events.spans.find { |span| span["name"] == "llm.call" }
  end

  it "returns the text and records tokens, cost and latency in an llm.call span" do
    client, = metered([
      JobSearch::LlmResponse.new(text: '{"steps":[]}', model: "gpt-x-2026-08-01", usage: usage(1_000, 500))
    ])

    expect(client.complete(prompt: "Create a plan")).to eq('{"steps":[]}')
    expect(call_span).to include(
      "status" => "ok", "model" => "gpt-x-2026-08-01", "usage_reported" => true,
      "input_tokens" => 1_000, "output_tokens" => 500, "total_tokens" => 1_500,
      "cached_input_tokens" => 0, "cost_usd" => 0.003
    )
    expect(call_span["duration_ms"]).to be >= 0
    expect(budget.total_tokens).to eq(1_500)
    expect(budget.cost_usd).to eq(0.003)
  end

  it "falls back to the configured model when the provider does not name it" do
    client, = metered([ JobSearch::LlmResponse.new(text: "{}", usage: usage(10, 10)) ])

    client.complete(prompt: "p")

    expect(call_span).to include("model" => "gpt-x", "cost_usd" => 0.00005)
  end

  it "leaves the cost out when the model has no price" do
    client, = metered([ JobSearch::LlmResponse.new(text: "{}", usage: usage(10, 10)) ], model: "unknown")

    client.complete(prompt: "p")

    expect(call_span).not_to have_key("cost_usd")
    expect(call_span["total_tokens"]).to eq(20)
  end

  it "flags calls whose usage was not reported" do
    client, = metered([ "{}" ])

    client.complete(prompt: "p")

    expect(call_span).to include("usage_reported" => false)
    expect(budget.calls).to eq(1)
  end

  it "charges a truncated response before the contract rejects it" do
    truncated = JobSearch::LlmResponse.new(
      text: "{", status: :incomplete, incomplete_reason: :max_output_tokens, usage: usage(100, 400)
    )
    client, = metered([ truncated ])

    expect { client.complete(prompt: "p") }.to raise_error(JobSearch::LlmIncompleteResponseError)
    expect(budget.total_tokens).to eq(500)
    expect(call_span).to include("status" => "ok", "response_status" => "incomplete", "output_tokens" => 400)
  end

  it "does not call the provider once the budget is spent" do
    budget.record(usage: usage(1_000, 0), cost_usd: nil)
    client, inner = metered([ "{}" ])

    expect { client.complete(prompt: "p") }.to raise_error(JobSearch::LlmBudgetExceeded)
    expect(inner.calls).to eq(0)
  end

  it "records a provider failure as an errored span without usage" do
    client, = metered([ JobSearch::LlmProviderError.new("down", transient: true) ])

    expect { client.complete(prompt: "p") }.to raise_error(JobSearch::LlmProviderError)
    expect(call_span).to include("status" => "error", "error_class" => "JobSearch::LlmProviderError")
    expect(budget.calls).to eq(0)
  end
end

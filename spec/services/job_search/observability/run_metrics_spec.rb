require "rails_helper"
require Rails.root.join("spec/support/job_search/captured_events")

RSpec.describe JobSearch::Observability::RunMetrics do
  let(:events) { JobSearch::CapturedEvents.new }
  let(:metrics) { described_class.new(event_logger: events.event_logger) }

  def span(name, parent: "root", **attributes)
    { name: name, trace_id: "run-1", parent_span_id: parent, status: "ok", duration_ms: 1.0, **attributes }
  end

  def llm_call(**attributes)
    span("llm.call", usage_reported: true, input_tokens: 100, cached_input_tokens: 20,
                     output_tokens: 50, total_tokens: 150, cost_usd: 0.001, **attributes)
  end

  def finish_run(**attributes)
    metrics.call(span("agent.run", parent: nil, run_status: "completed", duration_ms: 900.0, **attributes))
    events.all.find { |event| event["event"] == "run.metrics" }
  end

  it "summarizes the run when the root span finishes" do
    metrics.call(llm_call(duration_ms: 300.0))
    metrics.call(span("planning.attempt", status: "error"))
    metrics.call(llm_call(duration_ms: 500.0))
    metrics.call(span("planning.attempt"))
    metrics.call(span("step", duration_ms: 10.0))
    metrics.call(span("step", status: "error", duration_ms: 5.0))

    expect(finish_run).to include(
      "trace_id" => "run-1", "run_status" => "completed", "duration_ms" => 900.0,
      "planning_attempts" => 2, "llm_calls" => 2,
      "llm_latency_ms" => 800.0, "llm_latency_max_ms" => 500.0,
      "input_tokens" => 200, "cached_input_tokens" => 40, "output_tokens" => 100, "total_tokens" => 300,
      "usage_missing_calls" => 0, "cost_usd" => 0.002, "cost_complete" => true,
      "tool_calls" => 2, "failed_tool_calls" => 1, "tool_latency_ms" => 15.0
    )
  end

  it "does not report a partial cost when a call had no price" do
    metrics.call(llm_call)
    metrics.call(llm_call(cost_usd: nil))

    expect(finish_run).to include("cost_usd" => nil, "cost_complete" => false, "total_tokens" => 300)
  end

  it "counts calls whose usage was not reported" do
    metrics.call(span("llm.call", usage_reported: false))

    expect(finish_run).to include("llm_calls" => 1, "usage_missing_calls" => 1, "total_tokens" => 0)
  end

  it "starts from zero on the next run" do
    metrics.call(llm_call)
    finish_run

    metrics.call(span("agent.run", parent: nil, trace_id: "run-2"))

    expect(metrics.last_summary).to include(trace_id: "run-2", llm_calls: 0, total_tokens: 0)
  end
end

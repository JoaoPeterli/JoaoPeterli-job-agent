require "rails_helper"
require Rails.root.join("spec/support/job_search/captured_events")

RSpec.describe JobSearch::Observability::Tracer do
  let(:events) { JobSearch::CapturedEvents.new }
  let(:time) { [ 0.0 ] }

  let(:tracer) do
    sequence = 0
    described_class.new(
      event_logger: events.event_logger,
      clock: -> { time.first },
      id_generator: -> { "id-#{sequence += 1}" }
    )
  end

  it "emits a span with duration and status when it finishes" do
    result = tracer.span("work", trace_id: "run-1", size: 3) do
      time[0] = 12.5
      :done
    end

    expect(result).to eq(:done)
    expect(events.spans).to eq([
      {
        "timestamp" => events.spans.first["timestamp"],
        "event" => "span",
        "name" => "work",
        "trace_id" => "run-1",
        "span_id" => "id-1",
        "parent_span_id" => nil,
        "duration_ms" => 12.5,
        "status" => "ok",
        "size" => 3
      }
    ])
  end

  it "nests spans under the current span and inherits the trace" do
    tracer.span("parent", trace_id: "run-1") do
      tracer.span("child", trace_id: "ignored") { nil }
    end

    child, parent = events.spans

    expect(child).to include("name" => "child", "trace_id" => "run-1", "parent_span_id" => parent["span_id"])
    expect(parent).to include("name" => "parent", "parent_span_id" => nil)
  end

  it "generates a trace id for a root span without one" do
    tracer.span("root") { nil }

    expect(events.spans.first["trace_id"]).to eq("id-1")
  end

  it "records errors with the error class and re-raises" do
    expect do
      tracer.span("work", trace_id: "run-1") { raise IOError, "secret detail" }
    end.to raise_error(IOError)

    span = events.spans.first
    expect(span).to include("status" => "error", "error_class" => "IOError")
    expect(events.raw).not_to include("secret detail")
  end

  it "lets the block add attributes" do
    tracer.span("work", trace_id: "run-1") { |span| span.set(:items, 2) }

    expect(events.spans.first["items"]).to eq(2)
  end

  it "correlates logs with the current span" do
    tracer.span("work", trace_id: "run-1") do |span|
      tracer.log(:warn, event: "something.happened", detail: 1)
      expect(events.all.first).to include(
        "event" => "something.happened", "trace_id" => "run-1", "span_id" => span.span_id, "detail" => 1
      )
    end
  end

  it "logs without correlation outside a span" do
    tracer.log(:info, event: "standalone")

    expect(events.all.first.keys).not_to include("trace_id")
  end

  it "still filters sensitive attributes" do
    tracer.span("work", trace_id: "run-1", api_key: "sk-123") { nil }

    expect(events.spans.first["api_key"]).to eq("[FILTERED]")
  end
end

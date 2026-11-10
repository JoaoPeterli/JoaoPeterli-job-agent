require "rails_helper"
require Rails.root.join("spec/support/job_search/captured_events")

# Peças compartilhadas entre agentes que rodam em paralelo (Aula 43).
RSpec.describe "Thread safety of shared components" do
  def in_threads(count, &block)
    Array.new(count) { |index| Thread.new(index, &block) }.map(&:value)
  end

  describe JobSearch::Observability::Tracer do
    let(:events) { JobSearch::CapturedEvents.new }
    let(:tracer) { described_class.new(event_logger: events.event_logger) }

    def span_named(name)
      events.spans.find { |span| span["name"] == name }
    end

    it "parents worker spans to the coordinator span through #attach" do
      tracer.span("root", trace_id: "t1") do |root|
        in_threads(2) do |index|
          tracer.attach(root) { tracer.span("worker_#{index}") { tracer.span("inner_#{index}") { sleep 0.02 } } }
        end
      end

      root = span_named("root")
      2.times do |index|
        worker = span_named("worker_#{index}")
        expect(worker).to include("parent_span_id" => root["span_id"], "trace_id" => "t1")
        expect(span_named("inner_#{index}")["parent_span_id"]).to eq(worker["span_id"])
      end
    end

    it "keeps a separate span stack per thread" do
      in_threads(4) { |index| tracer.span("alone_#{index}") { sleep 0.02 } }

      expect(events.spans.map { |span| span["parent_span_id"] }).to all(be_nil)
    end

    it "does not keep stacks for threads that finished" do
      in_threads(3) { |index| tracer.span("s#{index}") { nil } }

      expect(tracer.instance_variable_get(:@stacks)).to be_empty
    end
  end

  describe JobSearch::Observability::RunMetrics do
    it "counts spans coming from many threads" do
      metrics = described_class.new(event_logger: JobSearch::CapturedEvents.new.event_logger)

      in_threads(8) do
        25.times { metrics.call(name: "llm.call", parent_span_id: "p", duration_ms: 1.0, total_tokens: 2, usage_reported: true) }
      end
      metrics.call(name: "agent.run", parent_span_id: nil, trace_id: "t", duration_ms: 1.0)

      expect(metrics.last_summary).to include(llm_calls: 200, total_tokens: 400)
    end
  end

  describe JobSearch::AuditTrail do
    it "keeps one valid chain when many threads record in the same run" do
      trail = described_class.new

      in_threads(4) { |index| 5.times { |n| trail.record(run_id: "team-1", event: "e#{index}_#{n}", outcome: "info") } }

      expect(trail.events("team-1").map(&:seq)).to eq((1..20).to_a)
      expect(trail.verify("team-1")).to be_valid
    end
  end

  describe JobSearch::IdempotencyStore do
    it "lets only one thread acquire the same key" do
      store = described_class.new

      tokens = in_threads(10) { store.acquire("apply_job:abc") }

      expect(tokens.compact.size).to eq(1)
    end
  end
end

require "rails_helper"

RSpec.describe JobSearch::AuditTrail do
  let(:trail) { described_class.new }

  def record_three(run_id = "run-1")
    trail.record(run_id: run_id, event: "run.started", outcome: "info", details: { objective_chars: 10 })
    trail.record(run_id: run_id, event: "tool.authorization", outcome: "allowed", details: { tool: "search_jobs" })
    trail.record(run_id: run_id, event: "run.finished", outcome: "completed", details: { status: "completed" })
  end

  describe "#record" do
    it "chains events of a run with sequential seqs and digests" do
      record_three

      events = trail.events("run-1")
      expect(events.map(&:seq)).to eq([ 1, 2, 3 ])
      expect(events.first.prev_digest).to be_nil
      expect(events[1].prev_digest).to eq(events[0].digest)
      expect(events[2].prev_digest).to eq(events[1].digest)
    end

    it "keeps a separate chain per run" do
      record_three("run-1")
      trail.record(run_id: "run-2", event: "run.started", outcome: "info")

      expect(trail.events("run-2").map(&:seq)).to eq([ 1 ])
    end

    it "continues an existing chain from another process" do
      record_three
      other_process = described_class.new

      other_process.record(run_id: "run-1", event: "run.started", outcome: "info")

      expect(trail.verify("run-1")).to be_valid
      expect(trail.events("run-1").last.seq).to eq(4)
    end

    it "refuses to fork the chain when two writers race for the same seq" do
      record_three
      stale = described_class.new
      stale.instance_variable_get(:@heads)["run-1"] = [ 2, trail.events("run-1")[1].digest ]

      expect { stale.record(run_id: "run-1", event: "late", outcome: "info") }
        .to raise_error(ActiveRecord::RecordNotUnique)
      expect(trail.verify("run-1")).to be_valid
    end

    it "filters secrets out of the details" do
      event = trail.record(
        run_id: "run-1", event: "run.started", outcome: "info",
        details: { api_key: "sk-secret", nested: { access_token: "abc" }, tool: "search_jobs" }
      )

      expect(event.reload.details).to eq(
        "api_key" => "[FILTERED]", "nested" => { "access_token" => "[FILTERED]" }, "tool" => "search_jobs"
      )
      expect(trail.verify("run-1")).to be_valid
    end
  end

  describe "#verify" do
    it "accepts an untouched chain" do
      record_three

      result = trail.verify("run-1")
      expect(result).to be_valid
      expect(result.events).to eq(3)
    end

    it "detects a modified event" do
      record_three
      AgentAuditEvent.where(run_id: "run-1", seq: 2).update_all(outcome: "denied")

      result = trail.verify("run-1")
      expect(result).not_to be_valid
      expect(result.broken_at_seq).to eq(2)
      expect(result.reason).to eq("event content was modified")
    end

    it "detects modified details even when the digest is recomputed for that row only" do
      record_three
      forged = trail.events("run-1")[1]
      attributes = forged.attributes.symbolize_keys.merge(details: { "tool" => "apply_job" })
      AgentAuditEvent.where(id: forged.id)
                     .update_all(details: { tool: "apply_job" }, digest: described_class.digest_for(attributes))

      result = trail.verify("run-1")
      expect(result.broken_at_seq).to eq(3)
      expect(result.reason).to eq("broken link to previous event")
    end

    it "detects a deleted event" do
      record_three
      AgentAuditEvent.where(run_id: "run-1", seq: 2).delete_all

      result = trail.verify("run-1")
      expect(result.broken_at_seq).to eq(3)
      expect(result.reason).to eq("missing or reordered event")
    end

    it "treats an unknown run as an empty valid chain" do
      expect(trail.verify("nope")).to have_attributes(valid?: true, events: 0)
    end
  end
end

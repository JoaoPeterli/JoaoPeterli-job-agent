require "rails_helper"

RSpec.describe JobSearch::PersistentMemoryStore do
  include ActiveSupport::Testing::TimeHelpers

  subject(:store) { described_class.new }

  let(:memory) do
    JobSearch::ShortTermMemory.new.tap do |memory|
      memory.record(:plan_rejected, "Attempt 1: Unknown tool: foo")
      memory.record(:plan_started, "1 steps: search")
    end
  end

  describe "#save" do
    it "persists every memory entry of the run" do
      inserted = store.save(run_id: "run-1", objective: "Ruby remoto", memory: memory)

      expect(inserted).to eq(2)
      expect(AgentMemoryEntry.where(run_id: "run-1").order(:seq).pluck(:seq, :kind, :content))
        .to eq([
          [ 1, "plan_rejected", "Attempt 1: Unknown tool: foo" ],
          [ 2, "plan_started", "1 steps: search" ]
        ])
    end

    it "is idempotent: saving again only adds new entries" do
      store.save(run_id: "run-1", objective: "Ruby remoto", memory: memory)
      memory.record(:run_finished, "status: completed")

      inserted = store.save(run_id: "run-1", objective: "Ruby remoto", memory: memory)

      expect(inserted).to eq(1)
      expect(AgentMemoryEntry.where(run_id: "run-1").count).to eq(3)
    end

    it "does nothing for an empty memory" do
      expect(
        store.save(run_id: "run-1", objective: "x", memory: JobSearch::ShortTermMemory.new)
      ).to eq(0)
    end
  end

  describe "#load" do
    it "restores the short-term memory of a run" do
      store.save(run_id: "run-1", objective: "Ruby remoto", memory: memory)

      restored = store.load("run-1")

      expect(restored.entries).to eq(memory.entries)
    end

    it "continues the sequence after the restored entries" do
      store.save(run_id: "run-1", objective: "Ruby remoto", memory: memory)

      restored = store.load("run-1")

      expect(restored.record(:event, "after restore").seq).to eq(3)
    end

    it "returns an empty memory for an unknown run" do
      expect(store.load("missing")).to be_empty
    end
  end

  describe "#candidates" do
    it "returns entries of the requested kinds, newest first, excluding a run" do
      store.save(run_id: "run-1", objective: "Ruby", memory: memory)
      travel 1.minute do
        other = JobSearch::ShortTermMemory.new
        other.record(:plan_rejected, "Attempt 1: Cycle detected")
        store.save(run_id: "run-2", objective: "Ruby", memory: other)
      end

      expect(store.candidates(kinds: [ :plan_rejected ], limit: 10).map(&:content))
        .to eq([ "Attempt 1: Cycle detected", "Attempt 1: Unknown tool: foo" ])

      expect(
        store.candidates(kinds: [ :plan_rejected ], limit: 10, exclude_run_id: "run-2").map(&:run_id)
      ).to eq([ "run-1" ])
    end
  end
end

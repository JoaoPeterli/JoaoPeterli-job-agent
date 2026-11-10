require "rails_helper"

RSpec.describe JobSearch::ShortTermMemory do
  subject(:memory) { described_class.new }

  it "rejects a non-positive window" do
    expect { described_class.new(max_entries: 0) }.to raise_error(ArgumentError)
  end

  it "starts empty" do
    expect(memory).to be_empty
    expect(memory.entries).to eq([])
  end

  it "records entries in chronological order with a sequence number" do
    memory.record(:plan_started, "2 steps")
    memory.record("step_completed", "search (search_jobs)")

    expect(memory.entries.map(&:seq)).to eq([ 1, 2 ])
    expect(memory.entries.map(&:kind)).to eq([ :plan_started, :step_completed ])
    expect(memory.entries.last.to_s).to eq("[step_completed] search (search_jobs)")
  end

  it "filters entries by kind" do
    memory.record(:plan_rejected, "a")
    memory.record(:step_completed, "b")
    memory.record(:plan_rejected, "c")

    expect(memory.of_kind(:plan_rejected).map(&:content)).to eq([ "a", "c" ])
  end

  it "evicts the oldest entries when the window is full" do
    memory = described_class.new(max_entries: 2)

    memory.record(:event, "one")
    memory.record(:event, "two")
    memory.record(:event, "three")

    expect(memory.entries.map(&:content)).to eq([ "two", "three" ])
    expect(memory.entries.first.seq).to eq(2)
    expect(memory.evicted_count).to eq(1)
  end

  it "stores a compact summary instead of raw content" do
    entry = memory.record(:event, "line one\n\n   line two")

    expect(entry.content).to eq("line one line two")
  end

  it "caps long content" do
    entry = memory.record(:event, "x" * 2_000)

    expect(entry.content.length).to eq(described_class::MAX_CONTENT_LENGTH)
    expect(entry.content).to end_with("...")
  end

  it "does not expose its internal list for mutation" do
    memory.record(:event, "one")

    expect { memory.entries << :hack }.to raise_error(FrozenError)
  end

  it "can be restored from persisted entries and continue the sequence" do
    entries = [
      described_class::Entry.new(seq: 4, kind: :plan_started, content: "1 steps: search"),
      described_class::Entry.new(seq: 5, kind: :step_completed, content: "search (search_jobs)")
    ]

    memory = described_class.new(entries: entries)

    expect(memory.entries).to eq(entries)
    expect(memory.record(:event, "next").seq).to eq(6)
  end
end

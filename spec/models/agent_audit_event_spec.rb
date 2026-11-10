require "rails_helper"

RSpec.describe AgentAuditEvent do
  let(:event) do
    JobSearch::AuditTrail.new.record(run_id: "run-1", event: "run.started", outcome: "info")
  end

  it "cannot be updated once written" do
    expect { event.update!(outcome: "denied") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "cannot be destroyed" do
    expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(described_class.count).to eq(1)
  end

  it "only accepts known outcomes" do
    record = described_class.new(run_id: "r", seq: 1, event: "e", outcome: "maybe", digest: "d", created_at: Time.current)

    expect(record).not_to be_valid
  end
end

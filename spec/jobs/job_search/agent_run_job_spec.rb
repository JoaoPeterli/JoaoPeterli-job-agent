require "rails_helper"

RSpec.describe JobSearch::AgentRunJob, type: :job do
  let(:harness) { instance_double(JobSearch::Harness) }

  before { allow(JobSearch::Harness).to receive(:new).and_return(harness) }

  it "executes the run through the harness" do
    allow(harness).to receive(:execute)

    described_class.perform_now("run-1")

    expect(harness).to have_received(:execute).with("run-1")
  end

  it "schedules a retry when the run hit a transient failure" do
    allow(harness).to receive(:execute).and_raise(JobSearch::RunRetryable, "provider down")

    described_class.perform_now("run-1")

    expect(described_class).to have_been_enqueued.with("run-1")
  end

  it "is enqueued by Harness#submit" do
    allow(JobSearch::Harness).to receive(:new).and_call_original

    run = JobSearch::Harness.new.submit(objective: "Vagas Ruby")

    expect(described_class).to have_been_enqueued.with(run.id)
  end
end

RSpec.describe JobSearch::AgentRunRecoveryJob, type: :job do
  it "recovers stale runs" do
    harness = instance_double(JobSearch::Harness, recover_stale!: [])
    allow(JobSearch::Harness).to receive(:new).and_return(harness)

    described_class.perform_now

    expect(harness).to have_received(:recover_stale!)
  end
end

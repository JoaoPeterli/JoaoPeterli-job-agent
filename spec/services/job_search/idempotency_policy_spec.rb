require "rails_helper"

RSpec.describe JobSearch::IdempotencyPolicy do
  describe "#call" do
    it "returns the cached result without executing again" do
      store = JobSearch::IdempotencyStore.new(
        ttl_seconds: 30
      )

      policy = described_class.new(store: store)

      executions = 0

      operation = lambda do
        executions += 1
        { success: true }
      end

      first_result = policy.call(key: "job-123") do
        operation.call
      end

      second_result = policy.call(key: "job-123") do
        operation.call
      end

      expect(first_result).to eq(success: true)
      expect(second_result).to eq(success: true)
      expect(executions).to eq(1)
    end
  end

  describe "#call with concurrent operations" do
  it "prevents execution when the operation is already in progress" do
    store = JobSearch::IdempotencyStore.new(
      ttl_seconds: 30
    )

    policy = described_class.new(store: store)

    token = store.acquire("job-123")

    expect(token).not_to be_nil

    expect do
      policy.call(key: "job-123") do
        raise "This operation should not execute"
      end
    end.to raise_error(
      JobSearch::IdempotencyPolicy::OperationInProgress
    )

    expect(store.completed?("job-123")).to be(false)
  end
end

describe "#call with ambiguous outcomes" do
  it "keeps the lease after a timeout with unknown outcome" do
    store = JobSearch::IdempotencyStore.new(
      ttl_seconds: 30
    )

    policy = described_class.new(store: store)

    expect do
      policy.call(key: "application-123") do
        raise Timeout::Error, "External service timed out"
      end
    end.to raise_error(Timeout::Error)

    expect(store.completed?("application-123")).to be(false)

    expect do
      policy.call(key: "application-123") do
        raise "Should not execute again"
      end
    end.to raise_error(
      JobSearch::IdempotencyPolicy::OperationInProgress
    )
  end
end

describe "#call after ambiguous timeout" do
  it "does not repeat an operation after its lease expires" do
    clock = instance_double(JobSearch::Clock)

    now = 1_000.0
    allow(clock).to receive(:now) { now }

    store = JobSearch::IdempotencyStore.new(
      ttl_seconds: 30,
      clock: clock
    )

    policy = described_class.new(store: store)

    expect do
      policy.call(key: "application-123") do
        raise Timeout::Error, "Unknown external outcome"
      end
    end.to raise_error(Timeout::Error)

    # Simula a passagem de 31 segundos.
    now += 31

    executions = 0

    expect do
      policy.call(key: "application-123") do
        executions += 1
        { submitted: true }
      end
    end.to raise_error(
      JobSearch::IdempotencyPolicy::OperationInProgress
    )

    expect(executions).to eq(0)
  end
end

describe "#call after ambiguous timeout" do
  it "blocks execution even after the original lease TTL" do
    now = 1_000.0

    clock = instance_double(JobSearch::Clock)
    allow(clock).to receive(:now) { now }

    store = JobSearch::IdempotencyStore.new(
      ttl_seconds: 30,
      clock: clock
    )

    policy = described_class.new(store: store)

    expect do
      policy.call(key: "application-123") do
        raise Timeout::Error, "Unknown outcome"
      end
    end.to raise_error(Timeout::Error)

    now += 31

    executions = 0

    expect do
      policy.call(key: "application-123") do
        executions += 1
      end
    end.to raise_error(
      JobSearch::IdempotencyPolicy::OperationInProgress
    )

    expect(executions).to eq(0)
  end
end

describe "uncertain operation reconciliation" do
  it "reconciles a confirmed external success" do
    store = JobSearch::IdempotencyStore.new(
      ttl_seconds: 30
    )

    policy = described_class.new(store: store)

    expect do
      policy.call(key: "application-456") do
        raise Timeout::Error, "Unknown outcome"
      end
    end.to raise_error(Timeout::Error)

    result = { application_id: 789, status: "submitted" }

    expect(
      store.reconcile_completed(
        "application-456",
        result: result
      )
    ).to eq(true)

    executions = 0

    cached_result = policy.call(key: "application-456") do
      executions += 1
      { application_id: 999 }
    end

    expect(cached_result).to eq(result)
    expect(executions).to eq(0)
  end
end
end

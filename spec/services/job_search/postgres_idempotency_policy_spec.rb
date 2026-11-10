
require "rails_helper"

RSpec.describe JobSearch::IdempotencyPolicy do
  let(:store_a) do
    JobSearch::PostgresIdempotencyStore.new(ttl_seconds: 30)
  end

  let(:store_b) do
    JobSearch::PostgresIdempotencyStore.new(ttl_seconds: 30)
  end

  let(:policy_a) { described_class.new(store: store_a) }
  let(:policy_b) { described_class.new(store: store_b) }

  let(:key) { "integration-apply-job-123" }

  it "reuses a result persisted by another policy instance" do
    executions = 0

    first_result = policy_a.call(key: key) do
      executions += 1
      { application_id: 789, status: "submitted" }
    end

    second_result = policy_b.call(key: key) do
      executions += 1
      { application_id: 999, status: "duplicated" }
    end

    expect(first_result).to eq(
      application_id: 789,
      status: "submitted"
    )

    expect(second_result).to eq(
      "application_id" => 789,
      "status" => "submitted"
    )

    expect(executions).to eq(1)

    operation = JobSearchOperation.find_by!(
      operation_key: key
    )

    expect(operation.status).to eq("completed")
  end

  it "prevents another policy from executing an active operation" do
    token = store_a.acquire(key)

    expect(token).not_to be_nil

    expect do
      policy_b.call(key: key) do
        raise "This operation must not execute"
      end
    end.to raise_error(
      JobSearch::IdempotencyPolicy::OperationInProgress
    )
  end

  it "does not execute an operation marked uncertain" do
    token = store_a.acquire(key)

    expect(store_a.mark_uncertain(key, token)).to be(true)

    expect do
      policy_b.call(key: key) do
        raise "This operation must not execute"
      end
    end.to raise_error(
      JobSearch::IdempotencyPolicy::OperationInProgress
    )
  end

  it "reuses a result after reconciliation" do
    token = store_a.acquire(key)

    store_a.mark_uncertain(key, token)

    store_a.reconcile_completed(
      key,
      result: { application_id: 789 }
    )

    result = policy_b.call(key: key) do
      raise "This operation must not execute"
    end

    expect(result).to eq(
      "application_id" => 789
    )
  end


describe "expired lease recovery policy" do
  let(:key) { "external-application-456" }

  it "blocks expired lease recovery for external operations" do
    store = JobSearch::PostgresIdempotencyStore.new(
      ttl_seconds: 30
    )

    token = store.acquire(key)
    expect(token).not_to be_nil

    JobSearchOperation
      .where(operation_key: key)
      .update_all(expires_at: 1.second.ago)

    policy = described_class.new(
      store: store,
      recover_expired: false
    )

    executions = 0

    expect do
      policy.call(key: key) do
        executions += 1
      end
    end.to raise_error(
      JobSearch::IdempotencyPolicy::OperationInProgress
    )

    expect(executions).to eq(0)
  end

  it "allows expired lease recovery for retryable operations" do
    store = JobSearch::PostgresIdempotencyStore.new(
      ttl_seconds: 30
    )

    token = store.acquire(key)
    expect(token).not_to be_nil

    JobSearchOperation
      .where(operation_key: key)
      .update_all(expires_at: 1.second.ago)

    policy = described_class.new(
      store: store,
      recover_expired: true
    )

    executions = 0

    result = policy.call(key: key) do
      executions += 1
      { jobs: [ "Ruby Developer" ] }
    end

    expect(executions).to eq(1)
    expect(result).to eq(
      jobs: [ "Ruby Developer" ]
    )

    expect(store.completed?(key)).to be(true)
  end
end
end

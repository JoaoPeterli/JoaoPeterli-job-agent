require "rails_helper"

RSpec.describe JobSearch::IdempotencyPolicy, "unexpected failures" do
  let(:store) { JobSearch::PostgresIdempotencyStore.new(ttl_seconds: 30) }
  let(:policy) { described_class.new(store: store) }
  let(:key) { "policy-failure-#{SecureRandom.uuid}" }

  def status
    JobSearchOperation.find_by!(operation_key: key).status
  end

  it "marks a side-effecting operation as uncertain after an unexpected error" do
    expect do
      policy.call(key: key, recover_expired: false, side_effects: true) do
        raise JobSearch::TransientError, "retries exhausted"
      end
    end.to raise_error(JobSearch::TransientError)

    expect(status).to eq("uncertain")
  end

  it "releases a read-only operation after an unexpected error" do
    expect do
      policy.call(key: key, side_effects: false) do
        raise "boom"
      end
    end.to raise_error(RuntimeError, "boom")

    expect(status).to eq("released")
    expect(store.acquire(key, recover_expired: false)).not_to be_nil
  end

  it "releases a side-effecting operation when the budget rejects the call" do
    expect do
      policy.call(key: key, recover_expired: false, side_effects: true) do
        raise JobSearch::ExecutionBudgetExceeded, "too many tool calls"
      end
    end.to raise_error(JobSearch::ExecutionBudgetExceeded)

    expect(status).to eq("released")
  end

  it "treats operations as side-effecting by default" do
    expect do
      policy.call(key: key, recover_expired: false) do
        raise "boom"
      end
    end.to raise_error(RuntimeError)

    expect(status).to eq("uncertain")
  end
end

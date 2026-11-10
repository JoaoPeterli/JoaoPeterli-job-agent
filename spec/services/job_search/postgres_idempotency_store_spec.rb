require "rails_helper"
RSpec.describe JobSearch::PostgresIdempotencyStore do
  let(:store) { described_class.new(ttl_seconds: 30) }

  describe "#acquire" do
    let(:key) { "acquire-operation-123" }

    it "allows only one acquisition for the same operation" do
      token = store.acquire(key)

      expect(token).to be_a(String)
      expect(store.acquire(key)).to be_nil

      expect(
        JobSearchOperation.where(operation_key: key).count
      ).to eq(1)
    end

    it "allows only one worker to acquire the same operation" do
      tokens = Queue.new
      ready = Queue.new
      start = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            tokens << store.acquire(key)
          end
        end
      end

      2.times { ready.pop }
      2.times { start << true }

      threads.each(&:value)

      results = 2.times.map { tokens.pop }

      expect(results.compact.size).to eq(1)

      expect(
        JobSearchOperation.where(operation_key: key).count
      ).to eq(1)
    end
  end

  describe "#renew" do
    let(:key) { "renew-operation-123" }

    it "renews an active lease with the correct token" do
      token = store.acquire(key)

      original_expiration = JobSearchOperation.find_by!(
        operation_key: key
      ).expires_at

      expect(store.renew(key, token)).to be(true)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.expires_at).to be > original_expiration
    end

    it "rejects renewal with an invalid token" do
      token = store.acquire(key)

      expect(token).not_to be_nil
      expect(store.renew(key, "invalid-token")).to be(false)
    end
  end

  describe "#complete" do
    let(:key) { "complete-operation-123" }

    let(:result) do
      { application_id: 789, status: "submitted" }
    end

    it "completes an active lease with the correct token" do
      token = store.acquire(key)

      expect(
        store.complete(key, token, result: result)
      ).to be(true)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("completed")
      expect(operation.result).to eq(result.stringify_keys)
      expect(store.acquire(key)).to be_nil
    end

    it "rejects completion with an invalid token" do
      store.acquire(key)

      expect(
        store.complete(key, "invalid-token", result: result)
      ).to be(false)
    end

    it "rejects completion after the lease expires" do
      token = store.acquire(key)

      JobSearchOperation
        .where(operation_key: key)
        .update_all(expires_at: 1.second.ago)

      expect(
        store.complete(key, token, result: result)
      ).to be(false)
    end

    it "rejects completion by an old worker" do
      old_token = store.acquire(key)

      JobSearchOperation
        .where(operation_key: key)
        .update_all(expires_at: 1.second.ago)

      new_token = store.acquire(key)

      expect(new_token).not_to be_nil
      expect(new_token).not_to eq(old_token)

      expect(
        store.complete(key, old_token, result: result)
      ).to be(false)

      expect(
        store.complete(key, new_token, result: result)
      ).to be(true)
    end
  end

  describe "#release" do
    let(:key) { "release-operation-123" }

    it "releases an active lease with the correct token" do
      token = store.acquire(key)

      expect(store.release(key, token)).to be(true)

      new_token = store.acquire(key)

      expect(new_token).not_to be_nil
      expect(new_token).not_to eq(token)
    end

    it "rejects release with an invalid token" do
      store.acquire(key)

      expect(store.release(key, "invalid-token")).to be(false)
      expect(store.acquire(key)).to be_nil
    end

    it "does not release a completed operation" do
      token = store.acquire(key)

      store.complete(
        key,
        token,
        result: { success: true }
      )

      expect(store.release(key, token)).to be(false)
      expect(store.acquire(key)).to be_nil
    end

    it "does not release a lease owned by another worker" do
      old_token = store.acquire(key)

      JobSearchOperation
        .where(operation_key: key)
        .update_all(expires_at: 1.second.ago)

      new_token = store.acquire(key)

      expect(new_token).not_to be_nil
      expect(store.release(key, old_token)).to be(false)
      expect(store.renew(key, new_token)).to be(true)
    end
  end

  describe "#mark_uncertain" do
    let(:key) { "uncertain-operation-123" }

    it "marks an active operation as uncertain" do
      token = store.acquire(key)

      expect(store.mark_uncertain(key, token)).to be(true)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("uncertain")
      expect(store.acquire(key)).to be_nil
    end

    it "rejects an invalid token" do
      store.acquire(key)

      expect(
        store.mark_uncertain(key, "invalid-token")
      ).to be(false)
    end

    it "rejects an old worker token" do
      old_token = store.acquire(key)

      JobSearchOperation
        .where(operation_key: key)
        .update_all(expires_at: 1.second.ago)

      new_token = store.acquire(key)

      expect(new_token).not_to be_nil

      expect(
        store.mark_uncertain(key, old_token)
      ).to be(false)

      expect(
        store.mark_uncertain(key, new_token)
      ).to be(true)
    end

    it "does not change completed operations" do
      token = store.acquire(key)

      store.complete(
        key,
        token,
        result: { success: true }
      )

      expect(
        store.mark_uncertain(key, token)
      ).to be(false)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("completed")
    end
  end

  describe "#reconcile_completed" do
    let(:key) { "reconcile-operation-123" }

    let(:result) do
      { application_id: 789, status: "submitted" }
    end

    it "reconciles an uncertain operation" do
      token = store.acquire(key)
      store.mark_uncertain(key, token)

      expect(
        store.reconcile_completed(key, result: result)
      ).to be(true)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("completed")
      expect(operation.result).to eq(result.stringify_keys)
      expect(store.acquire(key)).to be_nil
    end

    it "does not reconcile an active lease" do
      store.acquire(key)

      expect(
        store.reconcile_completed(key, result: result)
      ).to be(false)
    end

    it "does not overwrite a completed operation" do
      token = store.acquire(key)

      store.complete(
        key,
        token,
        result: { original: true }
      )

      expect(
        store.reconcile_completed(key, result: result)
      ).to be(false)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.result).to eq("original" => true)
    end

    it "does not create a missing operation" do
      expect(
        store.reconcile_completed(key, result: result)
      ).to be(false)

      expect(
        JobSearchOperation.exists?(operation_key: key)
      ).to be(false)
    end

    it "rejects completion after another worker takes over" do
  key = "reconciliation-#{SecureRandom.uuid}"

  operation = JobSearchOperation.create!(
    operation_key: key,
    status: "uncertain",
    operation_type: "apply_job"
  )

  lease = JobSearch::ReconciliationLease.new(
    ttl_seconds: 30
  )

  old_token = lease.acquire(key)

  expect(old_token).to be_present

  operation.update!(
    reconciliation_expires_at: 1.minute.ago
  )

  new_token = lease.acquire(key)

  expect(new_token).to be_present
  expect(new_token).not_to eq(old_token)

  expect(
    store.reconcile_completed(
      key,
      result: { status: "stale" },
      reconciliation_token: old_token
    )
  ).to be(false)

  operation.reload

  expect(operation.status).to eq("uncertain")
  expect(operation.reconciliation_token).to eq(new_token)

  expect(
    store.reconcile_completed(
      key,
      result: { status: "confirmed" },
      reconciliation_token: new_token
    )
  ).to be(true)

  expect(operation.reload.status).to eq("completed")
  expect(operation.result).to eq("status" => "confirmed")
end
  end

  describe "#completed?" do
    let(:key) { "completed-check-123" }

    it "returns true for a completed operation" do
      token = store.acquire(key)

      store.complete(
        key,
        token,
        result: { success: true }
      )

      expect(store.completed?(key)).to be(true)
    end

    it "returns false for an active operation" do
      store.acquire(key)

      expect(store.completed?(key)).to be(false)
    end

    it "returns false for a missing operation" do
      expect(store.completed?(key)).to be(false)
    end
  end

  describe "#completed_result" do
    let(:key) { "completed-result-123" }

    it "returns the persisted result" do
      token = store.acquire(key)

      store.complete(
        key,
        token,
        result: { application_id: 789 }
      )

      expect(
        store.completed_result(key)
      ).to eq("application_id" => 789)
    end

    it "returns nil for an incomplete operation" do
      store.acquire(key)

      expect(store.completed_result(key)).to be_nil
    end

    it "returns nil for a missing operation" do
      expect(store.completed_result(key)).to be_nil
    end
  end

  describe "#acquire with expired lease policy" do
    let(:key) { "expired-external-operation-123" }

    before do
      store.acquire(key)

      JobSearchOperation
        .where(operation_key: key)
        .update_all(expires_at: 1.second.ago)
    end

    it "blocks automatic recovery for external operations" do
      expect(
        store.acquire(key, recover_expired: false)
      ).to be_nil
    end

    it "allows recovery for retryable operations" do
      expect(
        store.acquire(key, recover_expired: true)
      ).not_to be_nil
    end
  end

  describe "#acquire with operation_type" do
    it "persists the operation type on acquisition" do
      key = "apply-job-#{SecureRandom.uuid}"

      token = store.acquire(
        key,
        operation_type: "apply_job"
      )

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(token).not_to be_nil
      expect(operation.operation_type).to eq("apply_job")
      expect(operation.status).to eq("leased")
    end

    it "rejects a different operation type for the same key" do
      key = "apply-job-#{SecureRandom.uuid}"

      store.acquire(
        key,
        operation_type: "apply_job"
      )

      expect {
        store.acquire(
          key,
          operation_type: "send_email"
        )
      }.to raise_error(
        ArgumentError,
        /Operation type mismatch/
      )

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.operation_type).to eq("apply_job")
      expect(operation.status).to eq("leased")
    end
  end


describe "#reconcile_completed with fencing token" do
  it "rejects a stale worker and accepts the current lease owner" do
    key = "fencing-#{SecureRandom.uuid}"

    JobSearchOperation.create!(
      operation_key: key,
      status: "uncertain",
      operation_type: "apply_job",
      reconciliation_token: "worker-b",
      reconciliation_expires_at: 1.minute.from_now
    )

    stale_result = store.reconcile_completed(
      key,
      result: { status: "stale" },
      reconciliation_token: "worker-a"
    )

    expect(stale_result).to be(false)

    expect(
      JobSearchOperation.find_by!(operation_key: key).status
    ).to eq("uncertain")

    current_result = store.reconcile_completed(
      key,
      result: { status: "confirmed" },
      reconciliation_token: "worker-b"
    )

    expect(current_result).to be(true)

    operation = JobSearchOperation.find_by!(
      operation_key: key
    )

    expect(operation.status).to eq("completed")
    expect(operation.result).to eq(
      "status" => "confirmed"
    )
  end
end
end

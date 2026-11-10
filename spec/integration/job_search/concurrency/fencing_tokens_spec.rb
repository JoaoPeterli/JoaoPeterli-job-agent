require "rails_helper"
require Rails.root.join("spec/support/job_search/concurrency_helpers")
require Rails.root.join("spec/support/job_search/fake_applications_client")

# Aula 25 — Fencing tokens e escrita atômica
RSpec.describe "Fencing tokens and atomic writes" do
  include JobSearch::ConcurrencyHelpers

  self.use_transactional_tests = false

  let(:prefix) { "fencing-#{SecureRandom.uuid}" }
  let(:key) { "#{prefix}:apply" }
  let(:store) { JobSearch::PostgresIdempotencyStore.new(ttl_seconds: 30) }

  after do
    JobSearchOperation
      .where("operation_key LIKE ?", "#{prefix}%")
      .delete_all
  end

  describe "monotonic fencing token" do
    it "starts at 1 and grows on every new acquisition" do
      first = store.acquire_lease(key)

      expect(first.fencing_token).to eq(1)

      expire_lease!(key)
      second = store.acquire_lease(key, recover_expired: true)

      expect(second.fencing_token).to eq(2)

      expect(store.release(key, second.token)).to be(true)
      third = store.acquire_lease(key)

      expect(third.fencing_token).to eq(3)
      expect(operation_row(key).fencing_token).to eq(3)
    end

    it "never resets the token when a lease is released" do
      lease = store.acquire_lease(key)

      store.release(key, lease.token)

      operation = operation_row(key)

      expect(operation.status).to eq("released")
      expect(operation.fencing_token).to eq(1)
      expect(operation.lease_token).to be_nil
    end

    it "lets a released operation be acquired even without expired-lease recovery" do
      lease = store.acquire_lease(key, recover_expired: false)
      store.release(key, lease.token)

      next_lease = store.acquire_lease(key, recover_expired: false)

      expect(next_lease.fencing_token).to eq(2)
    end

    it "does not increment the token when acquisition fails" do
      store.acquire_lease(key)

      expect(store.acquire_lease(key)).to be_nil
      expect(operation_row(key).fencing_token).to eq(1)
    end
  end

  describe "atomic compare-and-set writes" do
    it "rejects every write from a stale worker after a takeover" do
      stale = store.acquire_lease(key)

      expire_lease!(key)

      current = store.acquire_lease(key, recover_expired: true)

      expect(store.renew(key, stale.token)).to be(false)
      expect(store.complete(key, stale.token, result: { from: "stale" })).to be(false)
      expect(store.mark_uncertain(key, stale.token)).to be(false)
      expect(store.release(key, stale.token)).to be(false)
      expect(store.valid?(key, stale.token)).to be(false)

      operation = operation_row(key)

      expect(operation.status).to eq("leased")
      expect(operation.lease_token).to eq(current.token)
      expect(operation.fencing_token).to eq(2)

      expect(store.complete(key, current.token, result: { from: "current" })).to be(true)
      expect(store.completed_result(key)).to eq("from" => "current")
    end

    it "never takes over terminal or unresolved operations" do
      %w[completed uncertain needs_review].each do |status|
        status_key = "#{prefix}:#{status}"

        JobSearchOperation.create!(
          operation_key: status_key,
          status: status,
          expires_at: 1.hour.ago,
          fencing_token: 7
        )

        expect(
          store.acquire_lease(status_key, recover_expired: true)
        ).to be_nil

        operation = operation_row(status_key)

        expect(operation.status).to eq(status)
        expect(operation.fencing_token).to eq(7)
      end
    end

    it "keeps rejecting operation type mismatches" do
      store.acquire_lease(key, operation_type: :apply_job)
      expire_lease!(key)

      expect do
        store.acquire_lease(
          key,
          recover_expired: true,
          operation_type: :send_email
        )
      end.to raise_error(ArgumentError, /Operation type mismatch/)

      expect(operation_row(key).fencing_token).to eq(1)
    end
  end

  describe "fencing at the external resource" do
    let(:client) { JobSearch::FakeApplicationsClient.new }
    let(:tool) { JobSearch::ApplyJobTool.new(client: client) }

    it "uses the operation key as idempotency key and sends the fencing token" do
      lease = store.acquire_lease(key)

      tool.call(job_id: 1, candidate_id: 2, lease: lease)

      expect(client.requests.last).to eq(
        job_id: 1,
        candidate_id: 2,
        idempotency_key: key,
        fencing_token: 1
      )
    end

    it "rejects a write from a stale worker that arrives after the new owner" do
      stale = store.acquire_lease(key)
      expire_lease!(key)
      current = store.acquire_lease(key, recover_expired: true)

      result = tool.call(job_id: 1, candidate_id: 2, lease: current)

      expect do
        tool.call(job_id: 1, candidate_id: 2, lease: stale)
      end.to raise_error(JobSearch::StaleFencingTokenError)

      expect(result).to eq(application_id: 1, status: "submitted")
      expect(client.created_applications.size).to eq(1)
      expect(client.rejected_requests.map { |r| r[:fencing_token] }).to eq([ 1 ])
    end

    it "treats a stale fencing rejection as a permanent error" do
      expect(JobSearch::StaleFencingTokenError.ancestors)
        .to include(JobSearch::PermanentError)
    end
  end
end

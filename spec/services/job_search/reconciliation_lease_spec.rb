
require "rails_helper"
require "active_support/testing/time_helpers"

RSpec.describe JobSearch::ReconciliationLease do
  include ActiveSupport::Testing::TimeHelpers

  let(:lease) do
    described_class.new(ttl_seconds: 30)
  end

  let!(:operation) do
    JobSearchOperation.create!(
      operation_key: SecureRandom.uuid,
      status: "uncertain",
      operation_type: "apply_job"
    )
  end

  describe "#acquire" do
    it "acquires a lease for an uncertain operation" do
      token = lease.acquire(operation.operation_key)

      expect(token).to be_present

      operation.reload

      expect(operation.reconciliation_token).to eq(token)
      expect(operation.reconciliation_expires_at).to be_future
      expect(operation.reconciliation_attempts).to eq(1)
    end

    it "prevents another worker from acquiring an active lease" do
      first_token = lease.acquire(operation.operation_key)
      second_token = lease.acquire(operation.operation_key)

      expect(first_token).to be_present
      expect(second_token).to be_nil
      expect(operation.reload.reconciliation_attempts).to eq(1)
    end

    it "allows recovery after the lease expires" do
      first_token = lease.acquire(operation.operation_key)

      operation.update!(
        reconciliation_expires_at: 1.minute.ago
      )

      second_token = lease.acquire(operation.operation_key)

      expect(second_token).to be_present
      expect(second_token).not_to eq(first_token)
      expect(operation.reload.reconciliation_attempts).to eq(2)
    end

    it "does not acquire a lease for completed operations" do
      operation.update!(status: "completed")

      expect(lease.acquire(operation.operation_key)).to be_nil
    end

    it "respects the next reconciliation time" do
      operation.update!(
        next_reconciliation_at: 5.minutes.from_now
      )

      expect(lease.acquire(operation.operation_key)).to be_nil
    end
  end

  describe "#valid?" do
    it "rejects an old worker token after another worker acquires the lease" do
      old_token = lease.acquire(operation.operation_key)

      operation.update!(
        reconciliation_expires_at: 1.minute.ago
      )

      new_token = lease.acquire(operation.operation_key)

      expect(
        lease.valid?(operation.operation_key, old_token)
      ).to be(false)

      expect(
        lease.valid?(operation.operation_key, new_token)
      ).to be(true)
    end

    it "rejects an expired token even without another worker" do
      token = lease.acquire(operation.operation_key)

      operation.update!(
        reconciliation_expires_at: 1.minute.ago
      )

      expect(
        lease.valid?(operation.operation_key, token)
      ).to be(false)
    end
  end

  describe "#release" do
    it "releases a valid lease" do
      token = lease.acquire(operation.operation_key)

      expect(
        lease.release(operation.operation_key, token)
      ).to be(true)

      operation.reload

      expect(operation.reconciliation_token).to be_nil
      expect(operation.reconciliation_expires_at).to be_nil
    end

    it "rejects release when the lease has expired" do
      token = lease.acquire(operation.operation_key)

      expect(token).to be_present

      travel 31.seconds do
        expect(
          lease.release(operation.operation_key, token)
        ).to be(false)
      end

      operation.reload

      expect(operation.reconciliation_token).to eq(token)
      expect(operation.reconciliation_expires_at).to be_present
    end

    it "prevents an old worker from releasing a new worker's lease" do
      old_token = lease.acquire(operation.operation_key)

      operation.update!(
        reconciliation_expires_at: 1.minute.ago
      )

      new_token = lease.acquire(operation.operation_key)

      expect(new_token).to be_present

      expect(
        lease.release(operation.operation_key, old_token)
      ).to be(false)

      expect(operation.reload.reconciliation_token).to eq(new_token)
    end
  end


describe "#renew" do
  it "extends an active lease owned by the worker" do
    token = lease.acquire(operation.operation_key)

    expect(token).to be_present

    original_expiration =
      operation.reload.reconciliation_expires_at

    travel 10.seconds do
      expect(
        lease.renew(operation.operation_key, token)
      ).to be(true)

      expect(
        operation.reload.reconciliation_expires_at
      ).to be > original_expiration
    end
  end

  it "rejects renewal with an invalid token" do
    token = lease.acquire(operation.operation_key)

    expect(token).to be_present

    expect(
      lease.renew(operation.operation_key, "invalid-token")
    ).to be(false)

    expect(
      operation.reload.reconciliation_token
    ).to eq(token)
  end

  it "does not renew an expired lease" do
    token = lease.acquire(operation.operation_key)

    operation.update!(
      reconciliation_expires_at: 1.minute.ago
    )

    expect(
      lease.renew(operation.operation_key, token)
    ).to be(false)

    expect(
      operation.reload.reconciliation_expires_at
    ).to be_past
  end

  it "does not allow an old worker to renew a new worker's lease" do
    old_token = lease.acquire(operation.operation_key)

    operation.update!(
      reconciliation_expires_at: 1.minute.ago
    )

    new_token = lease.acquire(operation.operation_key)

    expect(new_token).to be_present
    expect(new_token).not_to eq(old_token)

    expect(
      lease.renew(operation.operation_key, old_token)
    ).to be(false)

    expect(
      operation.reload.reconciliation_token
    ).to eq(new_token)
  end
end
end

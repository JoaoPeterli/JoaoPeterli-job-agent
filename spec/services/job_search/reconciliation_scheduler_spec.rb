
require "rails_helper"

RSpec.describe JobSearch::ReconciliationScheduler do
  let(:key) { "reconciliation-#{SecureRandom.uuid}" }

  let(:lease) do
    JobSearch::ReconciliationLease.new(ttl_seconds: 30)
  end

  let(:scheduler) do
    described_class.new(
      backoff: JobSearch::ReconciliationBackoff.new(
        base_delay: 30,
        max_delay: 300
      )
    )
  end

  let!(:operation) do
    JobSearchOperation.create!(
      operation_key: key,
      status: "uncertain",
      operation_type: "apply_job"
    )
  end

  describe "#schedule_next" do
    it "schedules the next reconciliation using backoff" do
      token = lease.acquire(key)

      expect(token).not_to be_nil

      expect(
        scheduler.schedule_next(
          key: key,
          reconciliation_token: token
        )
      ).to be(true)

      operation.reload

      expect(operation.reconciliation_attempts).to eq(1)

      expect(operation.next_reconciliation_at)
        .to be_within(2.seconds).of(30.seconds.from_now)
    end

    it "increases the delay after another attempt" do
      operation.update!(
        reconciliation_attempts: 1
      )

      token = lease.acquire(key)

      expect(token).not_to be_nil

      scheduler.schedule_next(
        key: key,
        reconciliation_token: token
      )

      operation.reload

      expect(operation.reconciliation_attempts).to eq(2)

      expect(operation.next_reconciliation_at)
        .to be_within(2.seconds).of(60.seconds.from_now)
    end

    it "rejects a stale reconciliation token" do
      token = lease.acquire(key)

      result = scheduler.schedule_next(
        key: key,
        reconciliation_token: "invalid-token"
      )

      expect(result).to be(false)

      operation.reload

      expect(operation.next_reconciliation_at).to be_nil
      expect(operation.reconciliation_token).to eq(token)
    end

    it "rejects an expired reconciliation lease" do
      token = lease.acquire(key)

      operation.update!(
        reconciliation_expires_at: 1.minute.ago
      )

      result = scheduler.schedule_next(
        key: key,
        reconciliation_token: token
      )

      expect(result).to be(false)

      expect(operation.reload.next_reconciliation_at).to be_nil
    end


it "rejects scheduling from a worker that lost the lease" do
  # Worker A adquire o lease
  old_token = lease.acquire(key)

  expect(old_token).to be_present

  # Simulamos a expiração do lease de A
  operation.update!(
    reconciliation_expires_at: 1.minute.ago
  )

  # Worker B assume a operação
  new_token = lease.acquire(key)

  expect(new_token).to be_present
  expect(new_token).not_to eq(old_token)

  # Worker A tenta reagendar usando o token antigo
  result = scheduler.schedule_next(
    key: key,
    reconciliation_token: old_token
  )

  expect(result).to be(false)

  # O estado de B deve permanecer intacto
  operation.reload

  expect(operation.status).to eq("uncertain")
  expect(operation.reconciliation_token).to eq(new_token)
  expect(operation.reconciliation_expires_at).to be_future
  expect(operation.next_reconciliation_at).to be_nil
  expect(operation.reconciliation_attempts).to eq(2)
end
  end
end

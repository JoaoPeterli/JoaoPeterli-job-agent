
require "rails_helper"

RSpec.describe JobSearch::ReconciliationScheduler do
  let(:scheduler) { described_class.new }

  let(:lease) do
    JobSearch::ReconciliationLease.new(
      ttl_seconds: 30
    )
  end

  let(:key) { "reconciliation-limit-#{SecureRandom.uuid}" }

  let!(:operation) do
    JobSearchOperation.create!(
      operation_key: key,
      operation_type: "apply_job",
      status: "uncertain",
      reconciliation_attempts: 4
    )
  end

  describe "reconciliation attempt limit" do
    it "marks an operation for review after the fifth unknown result" do
      token = lease.acquire(key)

      expect(token).to be_present

      operation.reload

      expect(operation.reconciliation_attempts).to eq(5)

      result = scheduler.schedule_next(
        key: key,
        reconciliation_token: token
      )

      expect(result).to eq(true)

      operation.reload

      expect(operation.status).to eq("needs_review")
      expect(operation.next_reconciliation_at).to be_nil
    end

    it "continues scheduling when attempts remain" do
      operation.update!(
        reconciliation_attempts: 2
      )

      token = lease.acquire(key)

      expect(token).to be_present

      result = scheduler.schedule_next(
        key: key,
        reconciliation_token: token
      )

      expect(result).to eq(true)

      operation.reload

      expect(operation.status).to eq("uncertain")
      expect(operation.reconciliation_attempts).to eq(3)
      expect(operation.next_reconciliation_at).to be > Time.current
    end
  end
end

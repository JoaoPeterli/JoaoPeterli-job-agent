
require "rails_helper"

RSpec.describe JobSearch::ReconciliationDispatchClaim do
  let(:key) { "dispatch-#{SecureRandom.uuid}" }

  let!(:operation) do
    JobSearchOperation.create!(
      operation_key: key,
      status: "uncertain",
      operation_type: "apply_job"
    )
  end

  subject(:claim) do
    described_class.new(ttl_seconds: 60)
  end

  describe "#acquire" do
    it "acquires a dispatch claim for an eligible operation" do
      token = claim.acquire(key)

      expect(token).to be_present

      operation.reload

      expect(operation.reconciliation_dispatch_token).to eq(token)
      expect(operation.reconciliation_dispatch_expires_at).to be_future
    end

    it "does not acquire an active dispatch claim twice" do
      first_token = claim.acquire(key)
      second_token = claim.acquire(key)

      expect(first_token).to be_present
      expect(second_token).to be_nil
    end

    it "allows acquisition after the dispatch claim expires" do
      first_token = claim.acquire(key)

      operation.update!(
        reconciliation_dispatch_expires_at: 1.minute.ago
      )

      second_token = claim.acquire(key)

      expect(second_token).to be_present
      expect(second_token).not_to eq(first_token)
    end

    it "does not acquire an operation before its scheduled retry" do
      operation.update!(
        next_reconciliation_at: 5.minutes.from_now
      )

      expect(claim.acquire(key)).to be_nil
    end

    it "does not acquire an operation with an active execution lease" do
      operation.update!(
        reconciliation_token: SecureRandom.uuid,
        reconciliation_expires_at: 1.minute.from_now
      )

      expect(claim.acquire(key)).to be_nil
    end

    it "does not acquire a completed operation" do
      operation.update!(status: "completed")

      expect(claim.acquire(key)).to be_nil
    end


it "allows only one worker to acquire the claim concurrently" do
  # Este teste precisa de commits visíveis entre conexões.
  # Não execute dentro de uma transação de teste compartilhada.

  ready = Queue.new
  start = Queue.new
  results = Queue.new

  threads = 2.times.map do
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        worker_claim = described_class.new(
          ttl_seconds: 60
        )

        ready << true
        start.pop

        results << worker_claim.acquire(key)
      end
    end
  end

  2.times { ready.pop }
  2.times { start << true }

  threads.each(&:value)

  tokens = 2.times.map { results.pop }

  expect(tokens.compact.size).to eq(1)
  expect(tokens.count(nil)).to eq(1)
  expect(tokens.compact.first).to be_present
end
  end
end

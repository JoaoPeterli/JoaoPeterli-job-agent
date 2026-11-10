require "rails_helper"
require Rails.root.join("spec/support/job_search/concurrency_helpers")
require Rails.root.join("spec/support/job_search/fake_applications_client")

# Aulas 27 e 28 — Concorrência entre múltiplos workers,
# testes de corrida e falhas simultâneas.
#
# Cada corrida é repetida várias vezes com chaves novas: uma única
# execução pode passar por sorte, e a repetição aumenta a chance de
# exercitar intercalações diferentes no banco.
RSpec.describe "Multiple workers racing for the same operation" do
  include JobSearch::ConcurrencyHelpers
  include ActiveJob::TestHelper

  self.use_transactional_tests = false

  let(:workers) { 4 }
  let(:iterations) { 10 }

  let(:prefix) { "race-#{SecureRandom.uuid}" }
  let(:store) { JobSearch::PostgresIdempotencyStore.new(ttl_seconds: 30) }

  after do
    JobSearchOperation
      .where("operation_key LIKE ?", "#{prefix}%")
      .delete_all
  end

  describe "acquisition" do
    it "grants a new operation to exactly one worker" do
      iterations.times do |iteration|
        key = "#{prefix}:new:#{iteration}"

        leases = run_concurrently(workers) { store.acquire_lease(key) }

        winners = leases.compact

        expect(winners.size).to eq(1)
        expect(winners.first.fencing_token).to eq(1)
        expect(JobSearchOperation.where(operation_key: key).count).to eq(1)
        expect(operation_row(key).lease_token).to eq(winners.first.token)
      end
    end

    it "lets exactly one worker take over an expired lease" do
      iterations.times do |iteration|
        key = "#{prefix}:takeover:#{iteration}"

        store.acquire_lease(key)
        expire_lease!(key)

        leases = run_concurrently(workers) do
          store.acquire_lease(key, recover_expired: true)
        end

        winners = leases.compact

        expect(winners.size).to eq(1)
        expect(winners.first.fencing_token).to eq(2)
        expect(operation_row(key).fencing_token).to eq(2)
      end
    end

    it "lets exactly one worker reacquire a released operation" do
      iterations.times do |iteration|
        key = "#{prefix}:released:#{iteration}"

        lease = store.acquire_lease(key)
        store.release(key, lease.token)

        leases = run_concurrently(workers) do
          store.acquire_lease(key, recover_expired: false)
        end

        expect(leases.compact.size).to eq(1)
        expect(operation_row(key).fencing_token).to eq(2)
      end
    end
  end

  describe "side-effecting operation" do
    let(:policy) { JobSearch::IdempotencyPolicy.new(store: store) }
    let(:client) { JobSearch::FakeApplicationsClient.new }
    let(:tool) { JobSearch::ApplyJobTool.new(client: client) }

    it "creates the external application exactly once" do
      iterations.times do |iteration|
        key = "#{prefix}:apply:#{iteration}"

        outcomes = run_concurrently(workers) do
          capture_outcome do
            policy.call(
              key: key,
              recover_expired: false,
              operation_type: :apply_job
            ) do |lease|
              tool.call(job_id: iteration, candidate_id: 1, lease: lease)
            end
          end
        end

        successes = outcomes.reject { |outcome| outcome.is_a?(Exception) }
        failures = outcomes.select { |outcome| outcome.is_a?(Exception) }

        # Quem não executou recebe o resultado gravado (chaves string,
        # vindas do jsonb) ou OperationInProgress, nunca outro erro.
        expect(successes).not_to be_empty
        expect(failures).to all(be_a(JobSearch::IdempotencyPolicy::OperationInProgress))

        expect(operation_row(key).status).to eq("completed")
        expect(operation_row(key).fencing_token).to eq(1)
      end

      expect(client.created_applications.size).to eq(iterations)
      expect(client.requests.size).to eq(iterations)
    end
  end

  describe "simultaneous failures" do
    it "applies exactly one finalization when the owner races with itself" do
      # Ex.: o timeout dispara (mark_uncertain) enquanto a resposta chega
      # (complete) e um erro tenta liberar a chave (release).
      iterations.times do |iteration|
        key = "#{prefix}:finalize:#{iteration}"
        lease = store.acquire_lease(key)

        finalizations = [
          -> { store.complete(key, lease.token, result: { ok: true }) },
          -> { store.mark_uncertain(key, lease.token) },
          -> { store.release(key, lease.token) }
        ]

        results = run_concurrently(finalizations.size) do |index|
          finalizations[index].call
        end

        expect(results.count(true)).to eq(1)

        expected_status = %w[completed uncertain released][results.index(true)]

        expect(operation_row(key).status).to eq(expected_status)
        expect(operation_row(key).lease_token).to be_nil
      end
    end

    it "never lets completion and stale recovery both win" do
      recovery = JobSearch::StaleOperationRecoveryService.new

      iterations.times do |iteration|
        key = "#{prefix}:recovery:#{iteration}"
        lease = store.acquire_lease(key, operation_type: :apply_job)

        # Lease prestes a expirar: as duas escritas disputam a fronteira.
        JobSearchOperation
          .where(operation_key: key)
          .update_all(expires_at: Time.current + 0.02)

        completed, _recovered = run_concurrently(2) do |index|
          sleep(rand * 0.04)

          if index.zero?
            store.complete(key, lease.token, result: { ok: true })
          else
            recovery.call
          end
        end

        operation = operation_row(key)

        # O contador do recovery é global (pode incluir outras linhas),
        # então o desfecho é verificado pelo estado final desta operação.
        if completed
          expect(operation.status).to eq("completed")
          expect(operation.result).to eq("ok" => true)
        else
          expect(operation.status).to be_in(%w[leased uncertain])
          expect(operation.result).to be_nil
        end
      end
    end

    it "keeps the fencing token consistent when every worker fails permanently" do
      policy = JobSearch::IdempotencyPolicy.new(store: store)
      executions = Queue.new

      iterations.times do |iteration|
        key = "#{prefix}:permanent:#{iteration}"
        executed_before = executions.size

        outcomes = run_concurrently(workers) do
          capture_outcome do
            policy.call(key: key, recover_expired: false) do |lease|
              executions << lease.fencing_token
              raise JobSearch::PermanentError, "rejected by API"
            end
          end
        end

        executed = executions.size - executed_before
        operation = operation_row(key)

        expect(outcomes).to all(
          be_a(JobSearch::PermanentError)
            .or(be_a(JobSearch::IdempotencyPolicy::OperationInProgress))
        )

        # Cada execução corresponde a exatamente um incremento do token,
        # e nenhum lease ficou preso após as falhas.
        expect(executed).to be >= 1
        expect(operation.fencing_token).to eq(executed)
        expect(operation.status).to eq("released")
        expect(operation.lease_token).to be_nil
      end
    end
  end

  describe "reconciliation workers" do
    before { clear_enqueued_jobs }
    after { clear_enqueued_jobs }

    def create_uncertain(key)
      JobSearchOperation.create!(
        operation_key: key,
        status: "uncertain",
        operation_type: "apply_job"
      )
    end

    it "grants the reconciliation lease to exactly one worker" do
      iterations.times do |iteration|
        key = "#{prefix}:reconcile:#{iteration}"
        create_uncertain(key)

        lease = JobSearch::ReconciliationLease.new(ttl_seconds: 30)
        tokens = run_concurrently(workers) { lease.acquire(key) }

        expect(tokens.compact.size).to eq(1)
        expect(operation_row(key).reconciliation_attempts).to eq(1)
      end
    end

    it "dispatches each uncertain operation once across concurrent dispatchers" do
      keys = Array.new(6) { |index| "#{prefix}:dispatch:#{index}" }
      keys.each { |key| create_uncertain(key) }

      dispatched = run_concurrently(workers) do
        JobSearch::ReconciliationDispatcher.new.call
      end

      enqueued_keys = enqueued_jobs
        .select { |job| job[:job] == JobSearch::ReconciliationJob }
        .map { |job| job[:args].first }
        .select { |key| key.start_with?(prefix) }

      expect(dispatched.sum).to eq(keys.size)
      expect(enqueued_keys.sort).to eq(keys.sort)
    end
  end
end

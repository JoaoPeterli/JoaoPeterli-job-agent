require "rails_helper"
require Rails.root.join("spec/support/job_search/concurrency_helpers")
require Rails.root.join("spec/support/job_search/fake_applications_client")

# Aula 26 — Execution lease e workers obsoletos
RSpec.describe "Execution lease and stale workers" do
  include JobSearch::ConcurrencyHelpers

  self.use_transactional_tests = false

  let(:prefix) { "lease-#{SecureRandom.uuid}" }
  let(:key) { "#{prefix}:apply" }

  after do
    JobSearchOperation
      .where("operation_key LIKE ?", "#{prefix}%")
      .delete_all
  end

  describe "heartbeat" do
    # TTL curto para que o teste rode rápido. O intervalo segue a
    # recomendação de TTL / 3 (com folga).
    let(:ttl) { 0.6 }
    let(:interval) { 0.15 }
    let(:store) { JobSearch::PostgresIdempotencyStore.new(ttl_seconds: ttl) }

    it "keeps a long-running operation alive beyond the lease TTL" do
      policy = JobSearch::IdempotencyPolicy.new(
        store: store,
        heartbeat_interval: interval
      )

      result = policy.call(key: key) do
        sleep(ttl * 2)
        { done: true }
      end

      expect(result).to eq(done: true)
      expect(store.completed_result(key)).to eq("done" => true)
    end

    it "loses the lease without heartbeat when the operation outlives the TTL" do
      policy = JobSearch::IdempotencyPolicy.new(store: store)

      expect do
        policy.call(key: key) do
          sleep(ttl * 2)
          { done: true }
        end
      end.to raise_error(JobSearch::IdempotencyPolicy::CompletionFailed)

      expect(store.completed?(key)).to be(false)
    end

    it "detects a takeover and refuses to record the stale result" do
      policy = JobSearch::IdempotencyPolicy.new(
        store: store,
        heartbeat_interval: interval
      )

      new_owner = nil

      expect do
        policy.call(key: key) do |lease|
          expect(lease.fencing_token).to eq(1)

          # Simula uma pausa longa (GC, VM suspensa): o lease expira e
          # outro worker assume a operação.
          expire_lease!(key)
          new_owner = store.acquire_lease(key, recover_expired: true)

          # Tempo para o heartbeat tentar renovar e perceber a perda.
          sleep(interval * 3)

          { from: "stale" }
        end
      end.to raise_error(JobSearch::IdempotencyPolicy::LeaseLost)

      operation = operation_row(key)

      expect(operation.status).to eq("leased")
      expect(operation.lease_token).to eq(new_owner.token)
      expect(operation.fencing_token).to eq(2)
      expect(operation.result).to be_nil
    end

    it "renews periodically and stops when asked" do
      lease = store.acquire_lease(key)

      heartbeat = JobSearch::LeaseHeartbeat.new(
        store: store,
        lease: lease,
        interval: 0.05
      ).start

      sleep(0.3)
      heartbeat.stop

      expect(heartbeat.renewals).to be >= 2
      expect(heartbeat).not_to be_lost

      renewals = heartbeat.renewals
      sleep(0.15)

      expect(heartbeat.renewals).to eq(renewals)
    end
  end

  describe "stale worker waking up after a takeover" do
    let(:store) { JobSearch::PostgresIdempotencyStore.new(ttl_seconds: 30) }
    let(:policy) { JobSearch::IdempotencyPolicy.new(store: store) }
    let(:client) { JobSearch::FakeApplicationsClient.new }
    let(:tool) { JobSearch::ApplyJobTool.new(client: client) }

    it "has its external write rejected and cannot touch the new state" do
      acquired = Queue.new
      resume = Queue.new

      stale_worker = Thread.new do
        Thread.current.report_on_exception = false

        ActiveRecord::Base.connection_pool.with_connection do
          capture_outcome do
            policy.call(key: key, recover_expired: true) do |lease|
              acquired << lease
              resume.pop # pausa: o worker para de responder aqui

              tool.call(job_id: 10, candidate_id: 20, lease: lease)
            end
          end
        end
      end

      stale_lease = Timeout.timeout(5) { acquired.pop }

      # O lease do worker pausado expira e um novo worker assume.
      expire_lease!(key)

      new_result = policy.call(key: key, recover_expired: true) do |lease|
        expect(lease.fencing_token).to eq(stale_lease.fencing_token + 1)

        tool.call(job_id: 10, candidate_id: 20, lease: lease)
      end

      # O worker obsoleto acorda e tenta concluir o trabalho dele.
      resume << true
      stale_outcome = Timeout.timeout(5) { stale_worker.value }

      expect(stale_outcome).to be_a(JobSearch::StaleFencingTokenError)

      expect(client.created_applications.size).to eq(1)
      expect(client.rejected_requests.size).to eq(1)
      expect(client.rejected_requests.first[:fencing_token]).to eq(1)

      operation = operation_row(key)

      expect(operation.status).to eq("completed")
      expect(operation.fencing_token).to eq(2)
      expect(operation.result).to eq(new_result.deep_stringify_keys)
    ensure
      stale_worker&.kill
      stale_worker&.join
    end
  end

  describe "crashed worker" do
    let(:store) { JobSearch::PostgresIdempotencyStore.new(ttl_seconds: 30) }
    let(:recovery) { JobSearch::StaleOperationRecoveryService.new }

    it "moves only expired leases of external operations to uncertain" do
      live_key = "#{prefix}:live"
      crashed_key = "#{prefix}:crashed"

      store.acquire_lease(live_key, operation_type: :apply_job)
      store.acquire_lease(crashed_key, operation_type: :apply_job)

      expire_lease!(crashed_key)

      recovery.call

      expect(operation_row(live_key).status).to eq("leased")
      expect(operation_row(crashed_key).status).to eq("uncertain")
      expect(store.acquire_lease(crashed_key, recover_expired: false)).to be_nil
    end

    it "does not re-execute an external operation whose worker crashed" do
      policy = JobSearch::IdempotencyPolicy.new(store: store)

      expect do
        policy.call(key: key, recover_expired: false, operation_type: :apply_job) do
          raise IOError, "worker crashed mid-request"
        end
      end.to raise_error(IOError)

      expire_lease!(key)

      expect do
        policy.call(key: key, recover_expired: false, operation_type: :apply_job) do
          raise "must not run again"
        end
      end.to raise_error(JobSearch::IdempotencyPolicy::OperationInProgress)

      expect(operation_row(key).fencing_token).to eq(1)
    end
  end
end

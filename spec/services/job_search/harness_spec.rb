require "rails_helper"
require Rails.root.join("spec/support/job_search/scripted_llm_client")

RSpec.describe JobSearch::Harness do
  let(:objective) { "Encontrar vagas Ruby remotas" }
  let(:now) { [ Time.current ] }
  let(:clock) { -> { now.first } }
  let(:enqueued) { [] }
  let(:responses) { [ fixture("valid_full_plan.json") ] }
  let(:llm_client) { JobSearch::ScriptedLlmClient.new(responses) }
  let(:log) { StringIO.new }

  def fixture(name) = File.read(Rails.root.join("spec/fixtures/llm/plans", name))

  def harness(worker_id: "worker-1", client: llm_client)
    described_class.new(
      container_factory: lambda { |event_logger:, checkpoint:|
        JobSearch::Container.new(llm_client: client, event_logger: event_logger, checkpoint: checkpoint)
      },
      enqueue: ->(run) { enqueued << run.id },
      clock: clock,
      worker_id: worker_id,
      check_interval: 0,
      log_to: Logger.new(log)
    )
  end

  def advance(seconds) = now[0] += seconds

  describe "#submit" do
    it "stores the request and enqueues it once per idempotency key" do
      first = harness.submit(objective: objective, idempotency_key: "req-1")
      again = harness.submit(objective: objective, idempotency_key: "req-1")

      expect(again.id).to eq(first.id)
      expect(first).to have_attributes(status: "queued", mode: "agent", attempts: 0)
      expect(first.deadline_at).to be_within(1).of(now.first + described_class::DEFAULT_TIMEOUT_SECONDS)
      expect(enqueued).to eq([ first.id ])
    end

    it "refuses to reuse a key for a different request" do
      harness.submit(objective: objective, idempotency_key: "req-1")

      expect { harness.submit(objective: "Outra coisa", idempotency_key: "req-1") }
        .to raise_error(ArgumentError, /already used for a different request/)
    end
  end

  describe "#execute" do
    it "runs the agent and stores status, output and metrics" do
      run = harness.submit(objective: objective)

      finished = harness.execute(run.id)

      expect(finished).to have_attributes(status: "completed", attempts: 1, locked_by: nil, error_class: nil)
      expect(finished.result["output"].map { |job| job["title"] }).to eq([ "Senior Ruby Developer" ])
      expect(finished.metrics).to include("llm_calls" => 1, "tool_calls" => 3, "trace_id" => run.id)
      expect(finished.started_at).to be_present
      expect(finished.finished_at).to be_present
    end

    it "uses the run id as the trace and audit id" do
      run = harness.submit(objective: objective)

      harness.execute(run.id)

      expect(AgentAuditEvent.where(run_id: run.id).pluck(:event)).to include("run.started", "run.finished")
      expect(log.string).to include(%("event":"harness.run_finished"))
    end

    it "runs the supervisor team" do
      team_plan = JSON.generate(delegations: [
        { id: "search", agent: "researcher", task: "Search remote Ruby jobs", inputs: [] }
      ])
      client = JobSearch::ScriptedLlmClient.new([ team_plan, fixture("valid_search_only.json") ])
      run = harness.submit(objective: objective, mode: "supervisor")

      finished = harness(client: client).execute(run.id)

      expect(finished.status).to eq("completed")
      expect(finished.result["agents"].map { |agent| agent["delegation"] }).to eq([ "search" ])
      expect(finished.metrics).to include("llm_calls" => 2)
    end

    it "executes a run only once, even if the job is delivered twice" do
      run = harness.submit(objective: objective)

      harness.execute(run.id)

      expect(harness(worker_id: "worker-2").execute(run.id)).to be_nil
      expect(llm_client.calls).to eq(1)
    end

    it "does not let a second worker claim a run whose lease is still valid" do
      run = harness.submit(objective: objective)
      run.update_columns(status: "running", locked_by: "worker-1", locked_until: now.first + 60)

      expect(harness(worker_id: "worker-2").execute(run.id)).to be_nil
    end

    it "fails a run whose deadline passed while it waited in the queue" do
      run = harness.submit(objective: objective, timeout_seconds: 10)
      advance(11)

      finished = harness.execute(run.id)

      expect(finished).to have_attributes(status: "failed", error_class: "JobSearch::RunDeadlineExceeded")
      expect(llm_client.calls).to eq(0)
    end

    it "stops at the next checkpoint when the deadline passes during the run" do
      run = harness.submit(objective: objective, timeout_seconds: 10)
      allow_any_instance_of(JobSearch::SearchJobsTool).to receive(:call).and_wrap_original do |original, **args|
        advance(11)
        original.call(**args)
      end

      finished = harness.execute(run.id)

      expect(finished).to have_attributes(status: "failed", error_class: "JobSearch::RunDeadlineExceeded")
    end

    it "fails on a permanent error" do
      client = JobSearch::ScriptedLlmClient.new([ JobSearch::LlmProviderError.new("bad key", transient: false) ])
      run = harness.submit(objective: objective)

      finished = harness(client: client).execute(run.id)

      expect(finished).to have_attributes(status: "failed", error_class: "JobSearch::LlmProviderError")
      expect(finished.metrics).to include("run_status" => "failed")
    end

    it "requeues a transient failure for the job to retry, up to the attempt limit" do
      down = -> { JobSearch::ScriptedLlmClient.new([ JobSearch::LlmProviderError.new("503", transient: true) ]) }
      run = harness.submit(objective: objective)

      2.times do
        expect { harness(client: down.call).execute(run.id) }.to raise_error(JobSearch::RunRetryable) { |error|
          expect(error.cause).to be_a(JobSearch::LlmProviderError)
        }
        expect(run.reload).to have_attributes(status: "queued", locked_by: nil)
      end

      finished = harness(client: down.call).execute(run.id)
      expect(finished).to have_attributes(status: "failed", attempts: 3, error_class: "JobSearch::LlmProviderError")
    end
  end

  describe "#cancel" do
    it "cancels a queued run right away" do
      run = harness.submit(objective: objective)

      expect(harness.cancel(run.id).status).to eq("cancelled")
      expect(harness.execute(run.id)).to be_nil
      expect(llm_client.calls).to eq(0)
    end

    it "stops a running run at the next checkpoint, without starting new steps" do
      run = harness.submit(objective: objective)
      allow_any_instance_of(JobSearch::SearchJobsTool).to receive(:call).and_wrap_original do |original, **args|
        harness.cancel(run.id)
        original.call(**args)
      end
      allow(JobSearch::CandidateProfileTool).to receive(:new).and_call_original

      finished = harness.execute(run.id)

      expect(finished).to have_attributes(status: "cancelled", error_class: "JobSearch::RunCancelled")
      expect(JobSearch::CandidateProfileTool).not_to have_received(:new)
    end
  end

  describe "lease" do
    it "makes a worker that lost its lease stop without writing anything" do
      run = harness.submit(objective: objective)
      allow_any_instance_of(JobSearch::SearchJobsTool).to receive(:call).and_wrap_original do |original, **args|
        AgentRun.where(id: run.id).update_all(locked_by: "worker-2")
        original.call(**args)
      end

      harness.execute(run.id)

      expect(run.reload).to have_attributes(status: "running", locked_by: "worker-2", finished_at: nil)
    end

    it "requeues runs whose worker died, and gives up after the attempt limit" do
      stale = harness.submit(objective: objective)
      stale.update_columns(status: "running", locked_by: "dead", locked_until: now.first - 1, attempts: 1)
      exhausted = harness.submit(objective: "Vagas Rails", idempotency_key: "k2")
      exhausted.update_columns(status: "running", locked_by: "dead", locked_until: now.first - 1, attempts: 3)
      healthy = harness.submit(objective: "Vagas Go", idempotency_key: "k3")
      healthy.update_columns(status: "running", locked_by: "alive", locked_until: now.first + 30)
      enqueued.clear

      harness.recover_stale!

      expect(stale.reload).to have_attributes(status: "queued", locked_by: nil)
      expect(exhausted.reload).to have_attributes(status: "failed", error_class: "JobSearch::RunLeaseLost")
      expect(healthy.reload.status).to eq("running")
      expect(enqueued).to eq([ stale.id ])
    end
  end
end

require "rails_helper"

RSpec.describe JobSearch::RunCheckpoint do
  let(:now) { Time.zone.parse("2026-11-10 12:00:00") }
  let(:clock_time) { [ now ] }
  let(:clock) { -> { clock_time.first } }
  let(:run) do
    AgentRun.create!(mode: "agent", objective: "x", idempotency_key: SecureRandom.uuid,
                     status: "running", locked_by: "w1", locked_until: now + 60)
  end

  def checkpoint(**options)
    described_class.new(run_id: run.id, worker_id: "w1", lease_seconds: 60, clock: clock, check_interval: 1.0, **options)
  end

  def advance(seconds) = clock_time[0] += seconds

  it "renews the lease on each check (heartbeat)" do
    point = checkpoint
    advance(30)

    point.call("step")

    expect(run.reload.locked_until).to eq(now + 90)
  end

  it "goes to the database at most once per interval" do
    point = checkpoint
    point.call
    run.update_columns(locked_by: "w2")

    expect { point.call }.not_to raise_error
    advance(1)
    expect { point.call }.to raise_error(JobSearch::RunLeaseLost)
  end

  it "stops a run that was cancelled" do
    run.update_columns(cancel_requested_at: now)

    expect { checkpoint.call }.to raise_error(JobSearch::RunCancelled)
  end

  it "stops a run past its deadline without touching the database" do
    point = checkpoint(deadline_at: now + 10)
    advance(11)
    run.update_columns(locked_by: "someone-else")

    expect { point.call }.to raise_error(JobSearch::RunDeadlineExceeded)
  end

  it "is an interruption that internal retry policies do not catch" do
    expect(JobSearch::RunCancelled.ancestors).not_to include(JobSearch::PlanningError, JobSearch::TransientError)
  end
end

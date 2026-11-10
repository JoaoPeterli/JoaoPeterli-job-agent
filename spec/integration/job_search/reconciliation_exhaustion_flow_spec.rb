
require "rails_helper"

RSpec.describe "JobSearch reconciliation exhaustion flow", type: :job do
  include ActiveJob::TestHelper

  let(:key) { "exhaustion-#{SecureRandom.uuid}" }

  let!(:operation) do
    JobSearchOperation.create!(
      operation_key: key,
      operation_type: "apply_job",
      status: "uncertain",
      reconciliation_attempts: 4
    )
  end

  let(:checker) { double("ExternalChecker") }

  let(:service) do
    JobSearch::ReconciliationService.new(
      store: JobSearch::PostgresIdempotencyStore.new,
      checker: checker
    )
  end

  let(:container) do
    instance_double(JobSearch::ReconciliationContainer)
  end

  before do
    clear_enqueued_jobs
    clear_performed_jobs

    allow(JobSearch::ReconciliationContainer)
      .to receive(:configured)
      .and_return(container)

    allow(container)
      .to receive(:build)
      .with(operation_type: "apply_job")
      .and_return(service)

    allow(checker)
      .to receive(:call)
      .with(key: key)
      .and_return(status: :unknown)
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it "stops dispatching after five inconclusive attempts" do
    dispatcher = JobSearch::ReconciliationDispatcher.new

    expect(dispatcher.call).to eq(1)

    perform_enqueued_jobs(
      only: JobSearch::ReconciliationJob
    )

    operation.reload

    expect(operation.status).to eq("needs_review")
    expect(operation.reconciliation_attempts).to eq(5)
    expect(operation.next_reconciliation_at).to be_nil

    expect(operation.reconciliation_token).to be_nil
    expect(operation.reconciliation_expires_at).to be_nil

    expect(operation.reconciliation_dispatch_token).to be_nil
    expect(operation.reconciliation_dispatch_expires_at).to be_nil

    expect(dispatcher.call).to eq(0)

    expect {
      JobSearch::ReconciliationDispatcher.new.call
    }.not_to have_enqueued_job(
      JobSearch::ReconciliationJob
    )
  end

  it "rejects a stale token after entering manual review" do
    lease = JobSearch::ReconciliationLease.new
    token = lease.acquire(key)

    expect(token).to be_present

    scheduler = JobSearch::ReconciliationScheduler.new

    expect(
      scheduler.schedule_next(
        key: key,
        reconciliation_token: token
      )
    ).to eq(true)

    expect(operation.reload.status).to eq("needs_review")

    expect(
      scheduler.schedule_next(
        key: key,
        reconciliation_token: token
      )
    ).to eq(false)

    expect(lease.valid?(key, token)).to eq(false)
    expect(lease.acquire(key)).to be_nil
  end
end

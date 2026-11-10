
require "rails_helper"

RSpec.describe "JobSearch reconciliation retry flow", type: :job do
  include ActiveJob::TestHelper

  let(:key) { "retry-#{SecureRandom.uuid}" }

  let!(:operation) do
    JobSearchOperation.create!(
      operation_key: key,
      operation_type: "apply_job",
      status: "uncertain"
    )
  end

  let(:checker) { instance_double("ExternalChecker") }

  let(:store) do
    JobSearch::PostgresIdempotencyStore.new
  end

  let(:service) do
    JobSearch::ReconciliationService.new(
      store: store,
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

  it "schedules another reconciliation after an unknown response" do
    dispatcher = JobSearch::ReconciliationDispatcher.new

    expect(dispatcher.call).to eq(1)

    perform_enqueued_jobs(
      only: JobSearch::ReconciliationJob
    )

    operation.reload

    expect(operation.status).to eq("uncertain")
    expect(operation.reconciliation_attempts).to eq(1)
    expect(operation.next_reconciliation_at).to be > Time.current

    expect(dispatcher.call).to eq(0)

    operation.update!(
      next_reconciliation_at: 1.second.ago
    )

    expect(dispatcher.call).to eq(1)

    expect(JobSearch::ReconciliationJob)
      .to have_been_enqueued
      .with(key, an_instance_of(String))
  end
end

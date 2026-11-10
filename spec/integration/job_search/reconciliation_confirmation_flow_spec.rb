
require "rails_helper"

RSpec.describe "JobSearch reconciliation confirmation flow", type: :job do
  include ActiveJob::TestHelper

  let(:key) { "confirmation-#{SecureRandom.uuid}" }

  let!(:operation) do
    JobSearchOperation.create!(
      operation_key: key,
      operation_type: "apply_job",
      status: "uncertain"
    )
  end

  let(:checker) { double("ExternalChecker") }

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
      .and_return(
        { status: :unknown },
        {
          status: :confirmed,
          result: { application_id: "APP-123" }
        }
      )
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it "completes the operation after the second reconciliation" do
    dispatcher = JobSearch::ReconciliationDispatcher.new

    expect(dispatcher.call).to eq(1)

    perform_enqueued_jobs(
      only: JobSearch::ReconciliationJob
    )

    operation.reload

    expect(operation.status).to eq("uncertain")
    expect(operation.reconciliation_attempts).to eq(1)
    expect(operation.next_reconciliation_at).to be > Time.current

    operation.update!(
      next_reconciliation_at: 1.second.ago
    )

    expect(dispatcher.call).to eq(1)

    perform_enqueued_jobs(
      only: JobSearch::ReconciliationJob
    )

    operation.reload

    expect(operation.status).to eq("completed")
    expect(operation.result).to include(
      "application_id" => "APP-123"
    )

    expect(checker)
      .to have_received(:call)
      .with(key: key)
      .twice

    expect(dispatcher.call).to eq(0)
  end
end

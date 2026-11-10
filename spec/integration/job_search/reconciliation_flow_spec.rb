
require "rails_helper"

RSpec.describe "JobSearch reconciliation flow", type: :job do
  include ActiveJob::TestHelper

  let(:key) { "integration-#{SecureRandom.uuid}" }

  let(:operation) do
    JobSearchOperation.create!(
      operation_key: key,
      operation_type: "apply_job",
      status: "uncertain"
    )
  end

  let(:service) do
    instance_double(JobSearch::ReconciliationService)
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

    allow(service)
      .to receive(:call)
      .and_return(nil)
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it "dispatches and processes reconciliation with claim cleanup" do
    operation

    dispatched = JobSearch::ReconciliationDispatcher.new.call

    expect(dispatched).to eq(1)

    expect(JobSearch::ReconciliationJob)
      .to have_been_enqueued
      .with(key, an_instance_of(String))
      .exactly(:once)

    operation.reload

    expect(operation.reconciliation_dispatch_token)
      .to be_present

    expect(operation.reconciliation_dispatch_expires_at)
      .to be > Time.current

    perform_enqueued_jobs(
      only: JobSearch::ReconciliationJob
    )

    operation.reload

    expect(service)
      .to have_received(:call)
      .with(
        key: key,
        reconciliation_token: an_instance_of(String)
      )
      .once

    expect(operation.reconciliation_dispatch_token).to be_nil
    expect(operation.reconciliation_dispatch_expires_at).to be_nil

    expect(operation.reconciliation_token).to be_nil
    expect(operation.reconciliation_expires_at).to be_nil
  end
end

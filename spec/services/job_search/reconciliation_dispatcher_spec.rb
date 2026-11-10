
require "rails_helper"

RSpec.describe JobSearch::ReconciliationDispatcher do
  include ActiveJob::TestHelper

  let(:dispatcher) { described_class.new }

  before do
    clear_enqueued_jobs
  end

  after do
    clear_enqueued_jobs
  end

  describe "#call" do
    it "enqueues reconciliation for uncertain operations" do
      operation = JobSearchOperation.create!(
        operation_key: SecureRandom.uuid,
        status: "uncertain",
        operation_type: "apply_job"
      )

      expect {
        dispatcher.call
      }.to have_enqueued_job(
        JobSearch::ReconciliationJob
      ).with(
        operation.operation_key,
        an_instance_of(String)
      )

      operation.reload

      expect(operation.reconciliation_dispatch_token)
        .to be_present

      expect(enqueued_jobs.last[:args])
        .to eq([
          operation.operation_key,
          operation.reconciliation_dispatch_token
        ])
    end

    it "does not enqueue active leased operations" do
      JobSearchOperation.create!(
        operation_key: SecureRandom.uuid,
        status: "leased",
        operation_type: "apply_job",
        lease_token: SecureRandom.uuid,
        expires_at: 1.minute.from_now
      )

      expect {
        dispatcher.call
      }.not_to have_enqueued_job(
        JobSearch::ReconciliationJob
      )
    end

    it "does not enqueue completed operations" do
      JobSearchOperation.create!(
        operation_key: SecureRandom.uuid,
        status: "completed",
        operation_type: "apply_job"
      )

      expect {
        dispatcher.call
      }.not_to have_enqueued_job(
        JobSearch::ReconciliationJob
      )
    end

    it "ignores uncertain operations without operation_type" do
      JobSearchOperation.create!(
        operation_key: SecureRandom.uuid,
        status: "uncertain",
        operation_type: nil
      )

      expect {
        dispatcher.call
      }.not_to have_enqueued_job(
        JobSearch::ReconciliationJob
      )
    end
  end

  describe "reconciliation eligibility" do
    def create_uncertain_operation(attributes = {})
      JobSearchOperation.create!(
        {
          operation_key: SecureRandom.uuid,
          status: "uncertain",
          operation_type: "apply_job"
        }.merge(attributes)
      )
    end

    it "does not enqueue operations scheduled for the future" do
      operation = create_uncertain_operation(
        next_reconciliation_at: 5.minutes.from_now
      )

      expect {
        dispatcher.call
      }.not_to have_enqueued_job(
        JobSearch::ReconciliationJob
      )

      expect(operation.reload.reconciliation_dispatch_token)
        .to be_nil
    end

    it "enqueues operations whose scheduled time has arrived" do
      operation = create_uncertain_operation(
        next_reconciliation_at: 1.minute.ago
      )

      expect {
        dispatcher.call
      }.to have_enqueued_job(
        JobSearch::ReconciliationJob
      ).with(
        operation.operation_key,
        an_instance_of(String)
      )
    end

    it "does not enqueue operations with an active reconciliation lease" do
      operation = create_uncertain_operation(
        reconciliation_token: SecureRandom.uuid,
        reconciliation_expires_at: 1.minute.from_now
      )

      expect {
        dispatcher.call
      }.not_to have_enqueued_job(
        JobSearch::ReconciliationJob
      )

      expect(operation.reload.reconciliation_dispatch_token)
        .to be_nil
    end

    it "enqueues operations after their reconciliation lease expires" do
      operation = create_uncertain_operation(
        reconciliation_token: SecureRandom.uuid,
        reconciliation_expires_at: 1.minute.ago
      )

      expect {
        dispatcher.call
      }.to have_enqueued_job(
        JobSearch::ReconciliationJob
      ).with(
        operation.operation_key,
        an_instance_of(String)
      )
    end
  end

  describe "duplicate dispatch protection" do
    let(:key) { "dispatch-#{SecureRandom.uuid}" }

    let!(:operation) do
      JobSearchOperation.create!(
        operation_key: key,
        status: "uncertain",
        operation_type: "apply_job"
      )
    end

    it "does not enqueue the same operation twice within the claim window" do
      job = instance_double(JobSearch::ReconciliationJob)

      expect(JobSearch::ReconciliationJob)
        .to receive(:perform_later)
        .with(key, an_instance_of(String))
        .once
        .and_return(job)

      first_result = dispatcher.call
      second_result = dispatcher.call

      expect(first_result).to eq(1)
      expect(second_result).to eq(0)

      operation.reload

      expect(operation.reconciliation_dispatch_token)
        .to be_present

      expect(operation.reconciliation_dispatch_expires_at)
        .to be > Time.current
    end
  end

  describe "atomic dispatch claims" do
    let(:key) { "dispatch-#{SecureRandom.uuid}" }

    let!(:operation) do
      JobSearchOperation.create!(
        operation_key: key,
        status: "uncertain",
        operation_type: "apply_job"
      )
    end

    it "enqueues an operation only once while its dispatch claim is active" do
      job = instance_double(JobSearch::ReconciliationJob)

      expect(JobSearch::ReconciliationJob)
        .to receive(:perform_later)
        .with(key, an_instance_of(String))
        .once
        .and_return(job)

      first_result = dispatcher.call
      second_result = dispatcher.call

      expect(first_result).to eq(1)
      expect(second_result).to eq(0)

      operation.reload

      expect(operation.reconciliation_dispatch_token)
        .to be_present

      expect(operation.reconciliation_dispatch_expires_at)
        .to be > Time.current
    end

    it "releases its claim when enqueueing raises an exception" do
      allow(JobSearch::ReconciliationJob)
        .to receive(:perform_later)
        .with(key, an_instance_of(String))
        .and_raise(IOError, "Queue unavailable")

      expect {
        dispatcher.call
      }.to raise_error(
        IOError,
        "Queue unavailable"
      )

      operation.reload

      expect(operation.reconciliation_dispatch_token)
        .to be_nil

      expect(operation.reconciliation_dispatch_expires_at)
        .to be_nil
    end

    it "can enqueue again after its dispatch claim expires" do
      job = instance_double(JobSearch::ReconciliationJob)

      allow(JobSearch::ReconciliationJob)
        .to receive(:perform_later)
        .with(key, an_instance_of(String))
        .and_return(job)

      expect(dispatcher.call).to eq(1)

      first_token = operation.reload.reconciliation_dispatch_token

      operation.update!(
        reconciliation_dispatch_expires_at: 1.minute.ago
      )

      expect(dispatcher.call).to eq(1)

      second_token = operation.reload.reconciliation_dispatch_token

      expect(second_token).not_to eq(first_token)

      expect(JobSearch::ReconciliationJob)
        .to have_received(:perform_later)
        .with(key, an_instance_of(String))
        .twice
    end

    it "releases the claim when enqueueing returns false" do
      allow(JobSearch::ReconciliationJob)
        .to receive(:perform_later)
        .with(key, an_instance_of(String))
        .and_return(false)

      result = dispatcher.call

      expect(result).to eq(0)

      operation.reload

      expect(operation.reconciliation_dispatch_token)
        .to be_nil

      expect(operation.reconciliation_dispatch_expires_at)
        .to be_nil
    end
  end
end

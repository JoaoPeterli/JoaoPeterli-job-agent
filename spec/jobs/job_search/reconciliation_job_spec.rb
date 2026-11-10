
require "rails_helper"

RSpec.describe JobSearch::ReconciliationJob, type: :job do
  let(:service) do
    instance_double(JobSearch::ReconciliationService)
  end

  let(:container) do
    instance_double(JobSearch::ReconciliationContainer)
  end

  let(:key) { "apply-job-#{SecureRandom.uuid}" }

  before do
    allow(JobSearch::ReconciliationContainer)
      .to receive(:configured)
      .and_return(container)
  end

  def create_operation(status:, operation_type: "apply_job")
    JobSearchOperation.create!(
      operation_key: key,
      operation_type: operation_type,
      status: status
    )
  end

  describe "#perform" do
    it "reconciles an uncertain operation using the container" do
      create_operation(status: "uncertain")

      expect(container)
        .to receive(:build)
        .with(operation_type: "apply_job")
        .and_return(service)

      expect(service)
        .to receive(:call)
        .with(
          key: key,
          reconciliation_token: an_instance_of(String)
        )

      described_class.perform_now(key)
    end

    it "ignores a missing operation" do
      expect(JobSearch::ReconciliationContainer)
        .not_to receive(:configured)

      described_class.perform_now(key)
    end

    it "ignores a completed operation" do
      create_operation(status: "completed")

      expect(JobSearch::ReconciliationContainer)
        .not_to receive(:configured)

      described_class.perform_now(key)
    end

    it "ignores an operation without a type" do
      create_operation(
        status: "uncertain",
        operation_type: nil
      )

      expect(JobSearch::ReconciliationContainer)
        .not_to receive(:configured)

      described_class.perform_now(key)
    end
  end

  describe "reconciliation lease" do
    let(:lease) do
      JobSearch::ReconciliationLease.new(
        ttl_seconds: 30
      )
    end

    before do
      create_operation(status: "uncertain")
    end

    it "does not execute reconciliation when another worker owns the lease" do
      token = lease.acquire(key)

      expect(token).not_to be_nil

      expect(JobSearch::ReconciliationContainer)
        .not_to receive(:configured)

      described_class.perform_now(key)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("uncertain")
      expect(operation.reconciliation_token).to eq(token)
    end

    it "passes the actual acquired token to the service" do
      allow(container)
        .to receive(:build)
        .with(operation_type: "apply_job")
        .and_return(service)

      expect(service)
        .to receive(:call) do |key:, reconciliation_token:|
          operation = JobSearchOperation.find_by!(
            operation_key: key
          )

          expect(reconciliation_token).to be_present

          expect(operation.reconciliation_token)
            .to eq(reconciliation_token)

          expect(operation.reconciliation_expires_at)
            .to be > Time.current
        end

      described_class.perform_now(key)
    end

    it "releases the lease when reconciliation raises an exception" do
      allow(container)
        .to receive(:build)
        .with(operation_type: "apply_job")
        .and_return(service)

      allow(service)
        .to receive(:call)
        .and_raise(IOError, "External API unavailable")

      expect do
        described_class.perform_now(key)
      end.to raise_error(
        IOError,
        "External API unavailable"
      )

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("uncertain")
      expect(operation.reconciliation_token).to be_nil
      expect(operation.reconciliation_expires_at).to be_nil
    end
  end

  describe "dispatch claim cleanup" do
    let!(:operation) do
      create_operation(status: "uncertain")
    end

    let(:dispatch_claim) do
      JobSearch::ReconciliationDispatchClaim.new(
        ttl_seconds: 60
      )
    end

    before do
      allow(container)
        .to receive(:build)
        .with(operation_type: "apply_job")
        .and_return(service)

      allow(service)
        .to receive(:call)
        .and_return(nil)
    end

    it "releases its dispatch claim after reconciliation" do
      dispatch_token = dispatch_claim.acquire(key)

      expect(dispatch_token).to be_present

      described_class.perform_now(key, dispatch_token)

      operation.reload

      expect(operation.reconciliation_dispatch_token).to be_nil
      expect(operation.reconciliation_dispatch_expires_at).to be_nil
    end

    it "does not release a newer dispatch claim" do
      old_token = dispatch_claim.acquire(key)

      expect(old_token).to be_present

      newer_token = SecureRandom.uuid

      operation.update!(
        reconciliation_dispatch_token: newer_token
      )

      described_class.perform_now(key, old_token)

      operation.reload

      expect(operation.reconciliation_dispatch_token)
        .to eq(newer_token)

      expect(operation.reconciliation_dispatch_expires_at)
        .to be_present
    end

    it "releases its dispatch claim when reconciliation raises an exception" do
      dispatch_token = dispatch_claim.acquire(key)

      allow(service)
        .to receive(:call)
        .and_raise(IOError, "External API unavailable")

      expect do
        described_class.perform_now(key, dispatch_token)
      end.to raise_error(
        IOError,
        "External API unavailable"
      )

      operation.reload

      expect(operation.reconciliation_dispatch_token).to be_nil
      expect(operation.reconciliation_dispatch_expires_at).to be_nil

      expect(operation.reconciliation_token).to be_nil
      expect(operation.reconciliation_expires_at).to be_nil
    end


it "does not release dispatch claim when another worker owns the execution lease" do
  dispatch_token = dispatch_claim.acquire(key)

  expect(dispatch_token).to be_present

  execution_lease = JobSearch::ReconciliationLease.new(
    ttl_seconds: 30
  )

  execution_token = execution_lease.acquire(key)

  expect(execution_token).to be_present

  expect(container).not_to receive(:build)

  described_class.perform_now(key, dispatch_token)

  operation.reload

  expect(operation.reconciliation_token)
    .to eq(execution_token)

  expect(operation.reconciliation_dispatch_token)
    .to eq(dispatch_token)

  expect(operation.reconciliation_dispatch_expires_at)
    .to be > Time.current
end

it "releases dispatch claim when operation is already completed" do
  dispatch_token = dispatch_claim.acquire(key)

  expect(dispatch_token).to be_present

  operation.update!(status: "completed")

  expect(container).not_to receive(:build)

  described_class.perform_now(key, dispatch_token)

  operation.reload

  expect(operation.status).to eq("completed")

  expect(operation.reconciliation_dispatch_token).to be_nil

  expect(operation.reconciliation_dispatch_expires_at).to be_nil
end
  end
end

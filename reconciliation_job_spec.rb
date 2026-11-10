
require "rails_helper"

RSpec.describe JobSearch::ReconciliationJob, type: :job do
  let(:key) { "apply-job-#{SecureRandom.uuid}" }

  let(:service) do
    instance_double(JobSearch::ReconciliationService)
  end

  let(:factory) do
    double("reconciliation factory")
  end

  around do |example|
    previous_factory = described_class.service_factory
    described_class.service_factory = factory

    example.run
  ensure
    described_class.service_factory = previous_factory
  end

  def create_operation(status:, operation_type: "apply_job")
    JobSearchOperation.create!(
      operation_key: key,
      status: status,
      operation_type: operation_type
    )
  end

  it "reconciles an uncertain operation using its type" do
    create_operation(status: "uncertain")

    expect(factory)
      .to receive(:build)
      .with(operation_type: "apply_job")
      .and_return(service)

    expect(service)
      .to receive(:call)
      .with(key: key)

    described_class.perform_now(key)
  end

  it "ignores an operation that does not exist" do
    expect(factory).not_to receive(:build)

    expect(
      described_class.perform_now(key)
    ).to be_nil
  end

  it "does not reconcile a completed operation" do
    create_operation(status: "completed")

    expect(factory).not_to receive(:build)

    expect(
      described_class.perform_now(key)
    ).to be_nil
  end

  it "does not reconcile an active lease" do
    create_operation(status: "leased")

    expect(factory).not_to receive(:build)

    expect(
      described_class.perform_now(key)
    ).to be_nil
  end

  it "does not reconcile an operation without a type" do
    create_operation(
      status: "uncertain",
      operation_type: nil
    )

    expect(factory).not_to receive(:build)

    expect(
      described_class.perform_now(key)
    ).to be_nil
  end
end

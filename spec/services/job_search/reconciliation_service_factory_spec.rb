
require "rails_helper"

RSpec.describe JobSearch::ReconciliationServiceFactory do
  let(:checker) { double("reconciliation checker") }

  let(:reconciliation_token) do
    SecureRandom.uuid
  end

  let(:scheduler) do
    instance_double(
      JobSearch::ReconciliationScheduler,
      schedule_next: true
    )
  end

  subject(:factory) do
    described_class.new(checker: checker)
  end

  describe "#build" do
    it "builds a reconciliation service" do
      service = factory.build

      expect(service).to be_a(
        JobSearch::ReconciliationService
      )
    end


it "injects the checker into the service" do
  allow(JobSearch::ReconciliationScheduler)
    .to receive(:new)
    .and_return(scheduler)

  service = factory.build

  allow(checker)
    .to receive(:call)
    .with(key: "unknown-key")
    .and_return(status: :not_found)

  expect(
    service.call(
      key: "unknown-key",
      reconciliation_token: reconciliation_token
    )
  ).to be_nil

  expect(checker)
    .to have_received(:call)
    .with(key: "unknown-key")

  expect(scheduler)
    .to have_received(:schedule_next)
    .with(
      key: "unknown-key",
      reconciliation_token: reconciliation_token
    )
end
  end

  describe "registry integration" do
    let(:registry) do
      JobSearch::ReconciliationRegistry.new
    end

    let(:checker) do
      double("applications checker")
    end

    let(:store) do
      instance_double(
        JobSearch::PostgresIdempotencyStore
      )
    end

    subject(:registry_factory) do
      described_class.new(
        registry: registry,
        store: store
      )
    end


it "builds a service using the registered checker" do
  registry.register(:apply_job, checker)

  allow(JobSearch::ReconciliationScheduler)
    .to receive(:new)
    .and_return(scheduler)

  service = registry_factory.build(
    operation_type: :apply_job
  )

  allow(checker)
    .to receive(:call)
    .with(key: "application-123")
    .and_return(status: :not_found)

  expect(
    service.call(
      key: "application-123",
      reconciliation_token: reconciliation_token
    )
  ).to be_nil

  expect(checker)
    .to have_received(:call)
    .with(key: "application-123")

  expect(scheduler)
    .to have_received(:schedule_next)
    .with(
      key: "application-123",
      reconciliation_token: reconciliation_token
    )
end


    it "rejects an unregistered operation type" do
      expect {
        registry_factory.build(
          operation_type: :unknown
        )
      }.to raise_error(
        KeyError,
        /unknown/
      )
    end

    it "requires an operation type when using registry" do
      expect {
        registry_factory.build
      }.to raise_error(
        ArgumentError,
        /operation_type is required/
      )
    end
  end
end

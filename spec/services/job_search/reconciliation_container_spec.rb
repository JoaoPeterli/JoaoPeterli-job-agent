
require "rails_helper"

RSpec.describe JobSearch::ReconciliationContainer do
  let(:checker) do
    double("applications checker")
  end

  let(:registry) do
    JobSearch::ReconciliationRegistry.new.tap do |r|
      r.register(:apply_job, checker)
    end
  end

  subject(:container) do
    described_class.new(registry: registry)
  end

  it "builds a reconciliation service for a registered operation" do
    service = container.build(
      operation_type: :apply_job
    )

    expect(service).to be_a(
      JobSearch::ReconciliationService
    )
  end

  it "rejects an unknown operation type" do
    expect {
      container.build(operation_type: :unknown)
    }.to raise_error(KeyError)
  end
end


require "rails_helper"

RSpec.describe JobSearch::ReconciliationRegistry do
  subject(:registry) { described_class.new }

  let(:applications_checker) { double("applications checker") }
  let(:email_checker) { double("email checker") }

  describe "#register" do
    it "registers a checker for an operation type" do
      registry.register(:apply_job, applications_checker)

      expect(registry.fetch(:apply_job)).to eq(
        applications_checker
      )
    end

    it "supports different operation types" do
      registry.register(:apply_job, applications_checker)
      registry.register(:send_email, email_checker)

      expect(registry.fetch(:apply_job)).to eq(
        applications_checker
      )

      expect(registry.fetch(:send_email)).to eq(
        email_checker
      )
    end
  end

  describe "#fetch" do
    it "rejects an unknown operation type" do
      expect {
        registry.fetch(:unknown_operation)
      }.to raise_error(
        KeyError,
        /unknown_operation/
      )
    end
  end
end

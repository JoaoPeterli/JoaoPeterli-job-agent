
require "rails_helper"

RSpec.describe JobSearch::StaleOperationRecoveryService do
  let(:service) { described_class.new }

  let!(:operation) do
    JobSearchOperation.create!(
      operation_key: SecureRandom.uuid,
      status: "leased",
      operation_type: "apply_job",
      lease_token: SecureRandom.uuid,
      expires_at: 1.minute.ago
    )
  end

  describe "#call" do
    it "moves an expired leased operation to uncertain" do
      expect {
        service.call
      }.to change {
        operation.reload.status
      }.from("leased").to("uncertain")

      expect(operation.lease_token).to be_nil
      expect(operation.expires_at).to be_nil
    end

    it "does not change an active lease" do
      operation.update!(
        expires_at: 1.minute.from_now
      )

      service.call

      expect(operation.reload.status).to eq("leased")
    end

    it "does not change completed operations" do
      operation.update!(
        status: "completed",
        lease_token: nil,
        expires_at: nil
      )

      service.call

      expect(operation.reload.status).to eq("completed")
    end

    it "does not recover an expired operation without operation_type" do
      operation.update!(
        operation_type: nil
      )

      service.call

      expect(operation.reload.status).to eq("leased")
    end
  end
end

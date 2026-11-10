
require "rails_helper"

RSpec.describe JobSearchOperation, type: :model do
  describe "operation type" do
    it "persists the reconciliation operation type" do
      operation = described_class.create!(
        operation_key: "apply-job-#{SecureRandom.uuid}",
        operation_type: "apply_job",
        status: "uncertain"
      )

      operation.reload

      expect(operation.operation_type).to eq("apply_job")
      expect(operation.status).to eq("uncertain")
    end

    it "preserves compatibility with legacy operations" do
      operation = described_class.create!(
        operation_key: "legacy-#{SecureRandom.uuid}",
        status: "uncertain"
      )

      expect(operation.operation_type).to be_nil
    end
  end
end

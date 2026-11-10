
require "rails_helper"

RSpec.describe JobSearch::ApplyJobTool do
  let(:client) { instance_double("ApplicationsClient") }

  subject(:tool) do
    described_class.new(client: client)
  end

  describe "#call" do
    it "forwards the idempotency key to the external API" do
      expect(client).to receive(:create_application)
        .with(
          job_id: 123,
          candidate_id: 456,
          idempotency_key: "apply-job-123-candidate-456"
        )
        .and_return(
          application_id: 789,
          status: "submitted"
        )

      result = tool.call(
        job_id: 123,
        candidate_id: 456,
        idempotency_key: "apply-job-123-candidate-456"
      )

      expect(result).to eq(
        application_id: 789,
        status: "submitted"
      )
    end
  end
end

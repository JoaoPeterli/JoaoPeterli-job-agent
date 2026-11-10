
require "rails_helper"
require Rails.root.join(
  "spec/support/job_search/fake_applications_client"
)

RSpec.describe "Applications client lookup" do
  let(:client) do
    JobSearch::FakeApplicationsClient.new
  end

  let(:key) do
    "apply-job-123-candidate-456"
  end

  it "finds a previously submitted application" do
    created = client.create_application(
      job_id: 123,
      candidate_id: 456,
      idempotency_key: key
    )

    result = client.find_by_idempotency_key(
      idempotency_key: key
    )

    expect(result).to eq(created)
  end

  it "finds an application after its response was lost" do
    client.lose_next_response!

    expect do
      client.create_application(
        job_id: 123,
        candidate_id: 456,
        idempotency_key: key
      )
    end.to raise_error(Timeout::Error)

    result = client.find_by_idempotency_key(
      idempotency_key: key
    )

    expect(result).to eq(
      application_id: 1,
      status: "submitted"
    )

    expect(client.created_applications.size).to eq(1)
  end

  it "returns nil when the operation is unknown" do
    result = client.find_by_idempotency_key(
      idempotency_key: "unknown-operation"
    )

    expect(result).to be_nil
  end
end

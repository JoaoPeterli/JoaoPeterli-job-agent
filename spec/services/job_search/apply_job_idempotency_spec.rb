
require "rails_helper"
require Rails.root.join(
  "spec/support/job_search/fake_applications_client"
)

RSpec.describe "JobSearch::ApplyJobTool idempotency" do
  let(:client) do
    JobSearch::FakeApplicationsClient.new
  end

  let(:tool) do
    JobSearch::ApplyJobTool.new(client: client)
  end

  let(:arguments) do
    {
      job_id: 123,
      candidate_id: 456,
      idempotency_key: "apply-job-123-candidate-456"
    }
  end

  it "creates an application only once for repeated requests" do
    first_result = tool.call(**arguments)
    second_result = tool.call(**arguments)

    expect(first_result).to eq(second_result)
    expect(client.created_applications.size).to eq(1)
    expect(client.requests.size).to eq(2)
  end

  it "recovers the result after a lost response" do
    client.lose_next_response!

    expect do
      tool.call(**arguments)
    end.to raise_error(Timeout::Error, "Response lost")

    expect(client.created_applications.size).to eq(1)

    result = tool.call(**arguments)

    expect(result).to eq(
      application_id: 1,
      status: "submitted"
    )

    expect(client.created_applications.size).to eq(1)
    expect(client.requests.size).to eq(2)
  end

  it "rejects the same key with different arguments" do
    tool.call(**arguments)

    expect do
      tool.call(
        **arguments.merge(job_id: 999)
      )
    end.to raise_error(
      ArgumentError,
      "Idempotency key reused with different payload"
    )

    expect(client.created_applications.size).to eq(1)
  end
end

require "rails_helper"

RSpec.describe JobSearch::ProposeApplicationsJob do
  it "builds the proposer from the Container (public API) and proposes for the run" do
    run = AgentRun.create!(mode: "agent", objective: "x", idempotency_key: SecureRandom.uuid, status: "completed",
                           result: { "output" => [ { "title" => "Senior Rails", "company" => "A", "score" => 90 } ] })

    expect { described_class.perform_now(run.id) }.to change(JobApplication, :count).by(1)
    expect(JobApplication.sole).to have_attributes(status: "proposed", message: include("Senior Rails"))
  end
end

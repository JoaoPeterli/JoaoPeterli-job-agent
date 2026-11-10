require "rails_helper"

RSpec.describe JobSearch::Agent do
  let(:planner) { double("planner") }
  let(:plan_executor) { double("plan_executor") }
  let(:planning_retry_policy) { double("planning_retry_policy") }

  let(:agent) do
    described_class.new(
      objective: "Find remote Ruby jobs",
      planner: planner,
      plan_executor: plan_executor,
      planning_retry_policy: planning_retry_policy
    )
  end

  describe "#run" do
    it "generates a unique run_id for each execution" do
      states = []

      allow(planning_retry_policy)
        .to receive(:call)
        .and_yield(nil)

      allow(planner)
        .to receive(:plan)
        .and_return(:fake_plan)

      allow(plan_executor)
        .to receive(:execute) do |plan:, state:, **_kwargs|
          states << state
        end

      agent.run
      agent.run

      expect(states.length).to eq(2)
      expect(states.first.run_id).not_to be_nil
      expect(states.last.run_id).not_to be_nil
      expect(states.first.run_id).not_to eq(states.last.run_id)
    end
  end
end

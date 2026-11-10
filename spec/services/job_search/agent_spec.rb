require "rails_helper"

RSpec.describe JobSearch::Agent do
  let(:objective) do
    "Encontrar vagas Ruby"
  end

  let(:planner) do
    instance_double(
      JobSearch::LlmPlanner
    )
  end

  let(:plan_executor) do
    instance_double(
      JobSearch::PlanExecutor
    )
  end

  let(:planning_retry_policy) do
    JobSearch::PlanningRetryPolicy.new(
      max_attempts: 3
    )
  end

  let(:agent) do
    described_class.new(
      objective: objective,
      planner: planner,
      plan_executor: plan_executor,
      planning_retry_policy: planning_retry_policy
    )
  end

  describe "#objective" do
    it "returns the objective" do
      expect(
        agent.objective
      ).to eq(
        objective
      )
    end
  end

  describe "#run" do
    it "plans and executes the objective" do
      plan = instance_double(
        JobSearch::Plan
      )

      received_context = nil

      allow(planner)
        .to receive(:plan) do |context:|
          received_context = context

          plan
        end

      allow(plan_executor)
        .to receive(:execute)

      state = agent.run

      expect(
        received_context
      ).to be_a(
        JobSearch::PlanningContext
      )

      expect(
        received_context.objective
      ).to eq(
        objective
      )

      expect(
        received_context.attempt
      ).to eq(
        1
      )

      expect(
        received_context.previous_error
      ).to be_nil

      expect(plan_executor)
        .to have_received(:execute)
        .with(
          plan: plan,
          state: state
        )

      expect(state)
        .to be_a(
          JobSearch::AgentState
        )
    end

    it "retries planning with the previous error" do
      plan = instance_double(
        JobSearch::Plan
      )

      contexts = []

      allow(planner)
        .to receive(:plan) do |context:|
          contexts << context

          if context.attempt == 1
            raise JobSearch::PlanningError,
                  "Invalid LLM plan"
          end

          plan
        end

      allow(plan_executor)
        .to receive(:execute)

      state = agent.run

      expect(
        contexts.length
      ).to eq(
        2
      )

      first_context = contexts[0]
      second_context = contexts[1]

      expect(
        first_context.attempt
      ).to eq(
        1
      )

      expect(
        first_context.previous_error
      ).to be_nil

      expect(
        second_context.attempt
      ).to eq(
        2
      )

      expect(
        second_context.previous_error
      ).to be_a(
        JobSearch::PlanningError
      )

      expect(
        second_context.previous_error.message
      ).to eq(
        "Invalid LLM plan"
      )

      expect(planner)
        .to have_received(:plan)
        .twice

      expect(plan_executor)
        .to have_received(:execute)
        .with(
          plan: plan,
          state: state
        )
        .once
    end
  end
end

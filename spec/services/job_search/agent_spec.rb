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

    it "shares the run memory between planning and execution" do
      plan = instance_double(JobSearch::Plan)
      attempts = 0

      allow(planner).to receive(:plan) do |context:|
        attempts += 1
        next plan if attempts > 1

        raise JobSearch::PlanningError.new(
          "Invalid LLM plan",
          cause: JobSearch::PlanValidationError.new("Unknown tool: foo")
        )
      end

      executed_state = nil
      allow(plan_executor).to receive(:execute) do |plan:, state:|
        executed_state = state
      end

      state = agent.run

      expect(executed_state).to be(state)
      expect(state.memory.of_kind(:plan_rejected).map(&:content))
        .to eq([ "Attempt 1: Unknown tool: foo" ])
    end

    describe "persistent memory" do
      let(:plan) { instance_double(JobSearch::Plan) }
      let(:memory_store) { instance_double(JobSearch::PersistentMemoryStore, save: 1) }
      let(:memory_retriever) { instance_double(JobSearch::MemoryRetriever, lessons_for: []) }
      let(:event_logger) { instance_double(JobSearch::Observability::EventLogger, warn: nil) }

      let(:agent) do
        described_class.new(
          objective: objective,
          planner: planner,
          plan_executor: plan_executor,
          planning_retry_policy: planning_retry_policy,
          memory_store: memory_store,
          memory_retriever: memory_retriever,
          event_logger: event_logger
        )
      end

      before do
        allow(plan_executor).to receive(:execute) { |state:, **| state.complete! }
      end

      it "gives the planner lessons retrieved for the objective" do
        allow(memory_retriever).to receive(:lessons_for).and_return([ "Unknown tool: foo" ])
        received = nil
        allow(planner).to receive(:plan) { |context:| received = context; plan }

        state = agent.run

        expect(memory_retriever).to have_received(:lessons_for)
          .with(objective: objective, exclude_run_id: state.run_id)
        expect(received.lessons).to eq([ "Unknown tool: foo" ])
      end

      it "persists the run memory with the final status" do
        allow(planner).to receive(:plan).and_return(plan)

        state = agent.run

        expect(memory_store).to have_received(:save)
          .with(run_id: state.run_id, objective: objective, memory: state.memory)
        expect(state.memory.entries.last.to_s).to eq("[run_finished] status: completed")
      end

      it "persists the memory and marks the run failed when planning fails" do
        allow(planner).to receive(:plan)
          .and_raise(JobSearch::PlanningError.new("LLM down", retryable: false))

        expect { agent.run }.to raise_error(JobSearch::PlanningError)

        expect(memory_store).to have_received(:save) do |memory:, **|
          expect(memory.entries.last.to_s).to eq("[run_finished] status: failed")
        end
      end

      it "keeps running when lessons cannot be retrieved" do
        allow(memory_retriever).to receive(:lessons_for).and_raise(ActiveRecord::ConnectionNotEstablished)
        allow(planner).to receive(:plan).and_return(plan)

        expect(agent.run.status).to eq(:completed)
        expect(event_logger).to have_received(:warn)
          .with(hash_including(event: "agent_memory.retrieve_failed"))
      end

      it "does not fail the run when the memory cannot be saved" do
        allow(memory_store).to receive(:save).and_raise(ActiveRecord::ConnectionNotEstablished)
        allow(planner).to receive(:plan).and_return(plan)

        expect(agent.run.status).to eq(:completed)
        expect(event_logger).to have_received(:warn)
          .with(hash_including(event: "agent_memory.persist_failed"))
      end
    end
  end
end


require "rails_helper"

RSpec.describe JobSearch::PlanExecutor do
  let(:executor) { instance_double(JobSearch::Executor) }

  let(:execution_budget) do
    JobSearch::ExecutionBudget.new(
      max_steps: 10,
      max_tool_calls: 10
    )
  end

  let(:tool_catalog) do
    JobSearch::ToolCatalog.new(
      definitions: [
        JobSearch::ToolDefinition.new(
          name: :search_jobs,
          description: "Search jobs",
          side_effects: false
        ),
        JobSearch::ToolDefinition.new(
          name: :candidate_profile,
          description: "Candidate profile",
          side_effects: false
        ),
        JobSearch::ToolDefinition.new(
          name: :analyze_jobs,
          description: "Analyze jobs",
          side_effects: false
        ),
        JobSearch::ToolDefinition.new(
          name: :apply_job,
          description: "Apply to a job",
          side_effects: true,
          operation_type: :apply_job
        )
      ]
    )
  end

  let(:plan_executor) do
    described_class.new(
      executor: executor,
      execution_budget: execution_budget,
      tool_catalog: tool_catalog
    )
  end

  let(:state) do
    JobSearch::AgentState.new(
      objective: "Find remote Ruby jobs",
      run_id: "run-123"
    )
  end

  let(:search_action) do
    JobSearch::AgentAction.new(
      tool: :search_jobs,
      arguments: {
        technology: "Ruby",
        remote: true
      }
    )
  end

  let(:search_step) do
    JobSearch::Step.new(
      name: :search,
      action: search_action,
      dependencies: []
    )
  end

  let(:single_step_plan) do
    JobSearch::Plan.new(
      steps: [ search_step ]
    )
  end

  before do
    allow(executor)
      .to receive(:execute)
      .and_return([])
  end

  describe "#execute" do
    it "executes a plan with one step" do
      plan_executor.execute(
        plan: single_step_plan,
        state: state
      )

      expect(executor)
        .to have_received(:execute)
        .once

      expect(state.status).to eq(:completed)
    end

    it "executes multiple independent steps" do
      profile_step = JobSearch::Step.new(
        name: :profile,
        action: JobSearch::AgentAction.new(
          tool: :candidate_profile,
          arguments: {}
        ),
        dependencies: []
      )

      plan = JobSearch::Plan.new(
        steps: [ search_step, profile_step ]
      )

      plan_executor.execute(
        plan: plan,
        state: state
      )

      expect(executor)
        .to have_received(:execute)
        .twice

      expect(state.step_status(:search)).to eq(:completed)
      expect(state.step_status(:profile)).to eq(:completed)
    end

    it "executes dependent steps in dependency order" do
      profile_step = JobSearch::Step.new(
        name: :profile,
        action: JobSearch::AgentAction.new(
          tool: :candidate_profile,
          arguments: {}
        ),
        dependencies: [ :search ]
      )

      plan = JobSearch::Plan.new(
        steps: [ profile_step, search_step ]
      )

      executed_tools = []

      allow(executor)
        .to receive(:execute) do |action, **_kwargs|
          executed_tools << action.tool
          []
        end

      plan_executor.execute(
        plan: plan,
        state: state
      )

      expect(executed_tools).to eq(
        [ :search_jobs, :candidate_profile ]
      )
    end

    it "records the action and observation" do
      jobs = [
        { title: "Senior Ruby Developer" }
      ]

      allow(executor)
        .to receive(:execute)
        .and_return(jobs)

      plan_executor.execute(
        plan: single_step_plan,
        state: state
      )

      expect(state.actions).to include(search_action)
      expect(state.observation_for(:search)).to eq(jobs)
    end

    it "resolves observation references from previous steps" do
      jobs = [
        { title: "Ruby Developer" }
      ]

      analyze_step = JobSearch::Step.new(
        name: :analyze,
        action: JobSearch::AgentAction.new(
          tool: :analyze_jobs,
          arguments: {
            jobs: JobSearch::ObservationReference.new(
              step_name: :search
            )
          }
        ),
        dependencies: [ :search ]
      )

      plan = JobSearch::Plan.new(
        steps: [ search_step, analyze_step ]
      )

      allow(executor)
        .to receive(:execute) do |action, **_kwargs|
          action.tool == :search_jobs ? jobs : []
        end

      plan_executor.execute(
        plan: plan,
        state: state
      )

      expect(executor).to have_received(:execute).with(
        have_attributes(
          tool: :analyze_jobs,
          arguments: { jobs: jobs }
        ),
        hash_including(
          idempotency_key: "run-123:analyze"
        )
      )
    end

    it "marks the plan as failed when execution raises an error" do
      allow(executor)
        .to receive(:execute)
        .and_raise(StandardError, "Tool failed")

      expect do
        plan_executor.execute(
          plan: single_step_plan,
          state: state
        )
      end.to raise_error(
        StandardError,
        "Tool failed"
      )

      expect(state.status).to eq(:failed)
      expect(state.step_status(:search)).to eq(:failed)
    end

    it "does not execute dependent steps after a failure" do
      analyze_step = JobSearch::Step.new(
        name: :analyze,
        action: JobSearch::AgentAction.new(
          tool: :analyze_jobs,
          arguments: {}
        ),
        dependencies: [ :search ]
      )

      plan = JobSearch::Plan.new(
        steps: [ search_step, analyze_step ]
      )

      allow(executor)
        .to receive(:execute)
        .and_raise(StandardError, "Tool failed")

      expect do
        plan_executor.execute(
          plan: plan,
          state: state
        )
      end.to raise_error(
        StandardError,
        "Tool failed"
      )

      expect(executor)
        .to have_received(:execute)
        .once

      expect(state.status).to eq(:failed)
    end

    it "records the execution attempt for the step" do
      allow(executor)
        .to receive(:execute) do |_action, on_attempt:, idempotency_key:|
          expect(idempotency_key).to eq("run-123:search")

          on_attempt.call(1)

          []
        end

      plan_executor.execute(
        plan: single_step_plan,
        state: state
      )

      expect(state.attempts_for(:search)).to eq(1)
    end

    it "passes a stable idempotency key for each step" do
      expect(executor).to receive(:execute).with(
        an_instance_of(JobSearch::AgentAction),
        on_attempt: anything,
        idempotency_key: "run-123:search"
      ).and_return(
        [ { title: "Senior Ruby Developer" } ]
      )

      plan_executor.execute(
        plan: single_step_plan,
        state: state
      )

      expect(state.status).to eq(:completed)
    end

    it "uses different keys for different agent runs" do
      another_state = JobSearch::AgentState.new(
        objective: "Find remote Ruby jobs",
        run_id: "run-456"
      )

      keys = []

      allow(executor)
        .to receive(:execute) do |_action, **kwargs|
          keys << kwargs[:idempotency_key]
          []
        end

      plan_executor.execute(
        plan: single_step_plan,
        state: state
      )

      plan_executor.execute(
        plan: single_step_plan,
        state: another_state
      )

      expect(keys).to eq([
        "run-123:search",
        "run-456:search"
      ])
    end
  end

  describe "idempotency keys for side-effecting tools" do
    def apply_plan(step_name, job_id: 42)
      JobSearch::Plan.new(
        steps: [
          JobSearch::Step.new(
            name: step_name,
            action: JobSearch::AgentAction.new(
              tool: :apply_job,
              arguments: { job_id: job_id, candidate_id: 7 }
            ),
            dependencies: []
          )
        ]
      )
    end

    def keys_for(*runs)
      keys = []

      allow(executor).to receive(:execute) do |_action, **kwargs|
        keys << kwargs[:idempotency_key]
        {}
      end

      runs.each do |run_id, plan|
        plan_executor.execute(
          plan: plan,
          state: JobSearch::AgentState.new(objective: "Apply", run_id: run_id)
        )
      end

      keys
    end

    it "uses the same key across runs and step names for the same operation" do
      keys = keys_for(
        [ "run-1", apply_plan(:apply) ],
        [ "run-2", apply_plan(:submit_application) ]
      )

      expect(keys.uniq.length).to eq(1)
      expect(keys.first).to start_with("apply_job:")
      expect(keys.first).not_to include("run-1")
    end

    it "uses different keys for different operations" do
      keys = keys_for(
        [ "run-1", apply_plan(:apply, job_id: 1) ],
        [ "run-1", apply_plan(:apply, job_id: 2) ]
      )

      expect(keys.uniq.length).to eq(2)
    end
  end

  describe "execution budget" do
    it "restarts the budget for each plan execution" do
      clock = instance_double(JobSearch::Clock)
      now = 0.0
      allow(clock).to receive(:now) { now }

      budget = JobSearch::ExecutionBudget.new(
        max_steps: 10,
        max_execution_seconds: 30,
        clock: clock
      )

      budget.consume_tool_call!

      # O planejamento (ou uma execução anterior) levou mais que o limite.
      now = 100.0

      executor_with_budget = described_class.new(
        executor: executor,
        execution_budget: budget,
        tool_catalog: tool_catalog
      )

      allow(executor).to receive(:execute) do
        budget.validate_execution_time!
        []
      end

      executor_with_budget.execute(plan: single_step_plan, state: state)

      expect(state.status).to eq(:completed)
      expect(budget.tool_calls).to eq(0)
    end

    describe "short-term memory" do
      it "records the plan and each completed step" do
        plan_executor.execute(plan: single_step_plan, state: state)

        expect(state.memory.entries.map(&:to_s)).to eq([
          "[plan_started] 1 steps: search",
          "[step_completed] search (search_jobs)"
        ])
      end

      it "records a failed step with its error" do
        allow(executor).to receive(:execute).and_raise(IOError, "API down")

        expect do
          plan_executor.execute(plan: single_step_plan, state: state)
        end.to raise_error(IOError)

        expect(state.memory.of_kind(:step_failed).map(&:content)).to eq([
          "search (search_jobs): IOError: API down"
        ])
      end

      it "does not store raw observations in memory" do
        allow(executor).to receive(:execute)
          .and_return([ { title: "Senior Ruby Engineer at Secret Corp" } ])

        plan_executor.execute(plan: single_step_plan, state: state)

        expect(state.memory.entries.map(&:content).join).not_to include("Secret Corp")
      end
    end
  end
end

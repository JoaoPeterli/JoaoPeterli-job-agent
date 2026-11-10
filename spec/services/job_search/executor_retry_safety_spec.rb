
require "rails_helper"

RSpec.describe "JobSearch::Executor retry safety" do
  let(:attempts) { [] }

  let(:tool_class) do
    recorded_attempts = attempts

    Class.new do
      define_method(:call) do
        recorded_attempts << :called

        raise JobSearch::TransientError,
              "External service temporarily unavailable"
      end
    end
  end

  let(:registry) do
    JobSearch::ToolRegistry.new.tap do |registry|
      registry.register(:apply_job, tool_class)
    end
  end

  let(:definition) do
    JobSearch::ToolDefinition.new(
      name: :apply_job,
      description: "Apply for a job",
      schema: {},
      side_effects: side_effects
    )
  end

  let(:catalog) do
    JobSearch::ToolCatalog.new(
      definitions: [ definition ]
    )
  end

  let(:action) do
    JobSearch::AgentAction.new(
      tool: :apply_job,
      arguments: {}
    )
  end

  let(:executor) do
    JobSearch::Executor.new(
      registry: registry,
      retry_policy: JobSearch::RetryPolicy.new(
        max_attempts: 3,
        backoff_strategy: JobSearch::BackoffStrategy.new(
          base_delay: 0
        ),
        sleeper: JobSearch::Sleeper.new
      ),
      tool_catalog: catalog,
      tool_validator: JobSearch::ToolValidator.new,
      execution_budget: JobSearch::ExecutionBudget.new(
        max_steps: 10,
        max_tool_calls: 10
      ),
      timeout_policy: JobSearch::TimeoutPolicy.new(
        timeout_seconds: 5
      )
    )
  end

  context "when the tool has side effects" do
    let(:side_effects) { true }

    it "does not retry automatically" do
      expect do
        executor.execute(action)
      end.to raise_error(JobSearch::TransientError)

      expect(attempts.size).to eq(1)
    end
  end

  context "when the tool is read-only" do
    let(:side_effects) { false }

    it "allows automatic retries" do
      expect do
        executor.execute(action)
      end.to raise_error(JobSearch::TransientError)

      expect(attempts.size).to eq(3)
    end
  end
end

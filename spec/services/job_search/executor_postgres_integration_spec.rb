
require "rails_helper"

RSpec.describe "JobSearch::Executor PostgreSQL integration" do
  let(:executions) { [] }

  let(:tool_class) do
    calls = executions

    Class.new do
      define_method(:call) do |technology:, remote:|
        calls << { technology: technology, remote: remote }

        {
          technology: technology,
          remote: remote,
          jobs: [ "Senior Ruby Developer" ]
        }
      end
    end
  end

  let(:registry) do
    JobSearch::ToolRegistry.new.tap do |registry|
      registry.register(:search_jobs, tool_class)
    end
  end

  let(:definition) do
    JobSearch::ToolDefinition.new(
      name: :search_jobs,
      description: "Search for jobs",
      schema: {
        technology: String,
        remote: [ TrueClass, FalseClass ]
      }
    )
  end

  let(:catalog) do
    JobSearch::ToolCatalog.new(
      definitions: [ definition ]
    )
  end

  let(:action) do
    JobSearch::AgentAction.new(
      tool: :search_jobs,
      arguments: {
        technology: "Ruby",
        remote: true
      }
    )
  end

  let(:store_a) do
    JobSearch::PostgresIdempotencyStore.new(
      ttl_seconds: 30
    )
  end

  let(:store_b) do
    JobSearch::PostgresIdempotencyStore.new(
      ttl_seconds: 30
    )
  end

  def build_executor(store:)
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
      ),
      idempotency_policy: JobSearch::IdempotencyPolicy.new(
        store: store
      )
    )
  end

  describe "#execute" do
    let(:key) { "executor-postgres-search-ruby-123" }

    it "executes a tool only once across two executors" do
      executor_a = build_executor(store: store_a)
      executor_b = build_executor(store: store_b)

      first_result = executor_a.execute(
        action,
        idempotency_key: key
      )

      second_result = executor_b.execute(
        action,
        idempotency_key: key
      )

      expect(first_result).to eq(
        technology: "Ruby",
        remote: true,
        jobs: [ "Senior Ruby Developer" ]
      )

      expect(second_result).to eq(
        "technology" => "Ruby",
        "remote" => true,
        "jobs" => [ "Senior Ruby Developer" ]
      )

      expect(executions.size).to eq(1)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("completed")
    end

    it "blocks execution when another worker owns the lease" do
      token = store_a.acquire(key)

      expect(token).not_to be_nil

      executor_b = build_executor(store: store_b)

      expect do
        executor_b.execute(
          action,
          idempotency_key: key
        )
      end.to raise_error(
        JobSearch::IdempotencyPolicy::OperationInProgress
      )

      expect(executions).to be_empty
    end

    it "does not execute an uncertain operation" do
      token = store_a.acquire(key)

      expect(store_a.mark_uncertain(key, token)).to be(true)

      executor_b = build_executor(store: store_b)

      expect do
        executor_b.execute(
          action,
          idempotency_key: key
        )
      end.to raise_error(
        JobSearch::IdempotencyPolicy::OperationInProgress
      )

      expect(executions).to be_empty
    end

    it "reuses a reconciled result without executing the tool" do
      token = store_a.acquire(key)

      store_a.mark_uncertain(key, token)

      store_a.reconcile_completed(
        key,
        result: {
          technology: "Ruby",
          remote: true,
          jobs: [ "Senior Ruby Developer" ]
        }
      )

      executor_b = build_executor(store: store_b)

      result = executor_b.execute(
        action,
        idempotency_key: key
      )

      expect(result).to eq(
        "technology" => "Ruby",
        "remote" => true,
        "jobs" => [ "Senior Ruby Developer" ]
      )

      expect(executions).to be_empty
    end
  end


describe "expired lease safety" do
  let(:key) { "executor-safety-#{SecureRandom.uuid}" }

  let(:definition) do
    JobSearch::ToolDefinition.new(
      name: :search_jobs,
      description: "Search for jobs",
      schema: {
        technology: String,
        remote: [ TrueClass, FalseClass ]
      },
      side_effects: side_effects
    )
  end

  before do
    # Simula outro worker que adquiriu o lease.
    token = store_a.acquire(key)
    expect(token).not_to be_nil

    # Simula a expiração do lease.
    JobSearchOperation
      .where(operation_key: key)
      .update_all(expires_at: 1.second.ago)
  end

  context "when the tool is read-only" do
    let(:side_effects) { false }

    it "recovers the expired lease and executes" do
      result = build_executor(store: store_b).execute(
        action,
        idempotency_key: key
      )

      expect(result[:jobs]).to eq(
        [ "Senior Ruby Developer" ]
      )

      expect(executions.size).to eq(1)
      expect(store_b.completed?(key)).to be(true)
    end
  end

  context "when the tool has side effects" do
    let(:side_effects) { true }

    it "blocks automatic recovery" do
      expect do
        build_executor(store: store_b).execute(
          action,
          idempotency_key: key
        )
      end.to raise_error(
        JobSearch::IdempotencyPolicy::OperationInProgress
      )

      expect(executions).to be_empty
      expect(store_b.completed?(key)).to be(false)
    end
  end
end
end

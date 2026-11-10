
require "rails_helper"

RSpec.describe "JobSearch Idempotency Reconciliation" do
  it "reconciles a timed-out Executor operation without executing it twice" do
    store = JobSearch::PostgresIdempotencyStore.new

    policy = JobSearch::IdempotencyPolicy.new(
      store: store
    )

    key = "integration-apply-job-#{SecureRandom.uuid}"
    executions = 0

    tool_class = Class.new do
      define_method(:call) do |job_id:|
        executions += 1

        raise Timeout::Error, "External API timeout"
      end
    end

    registry = JobSearch::ToolRegistry.new
    registry.register(:submit_application, tool_class)

    definition = JobSearch::ToolDefinition.new(
      name: :submit_application,
      description: "Submit a job application",
      schema: {
        job_id: String
      },
      side_effects: true,
      operation_type: :apply_job
    )

    catalog = JobSearch::ToolCatalog.new(
      definitions: [ definition ]
    )

    retry_policy = JobSearch::RetryPolicy.new(
      max_attempts: 3,
      backoff_strategy: JobSearch::BackoffStrategy.new(
        base_delay: 0
      ),
      sleeper: JobSearch::Sleeper.new
    )

    executor = JobSearch::Executor.new(
      registry: registry,
      retry_policy: retry_policy,
      tool_catalog: catalog,
      tool_validator: JobSearch::ToolValidator.new,
      execution_budget: JobSearch::ExecutionBudget.new(
        max_steps: 10,
        max_tool_calls: 10
      ),
      timeout_policy: JobSearch::TimeoutPolicy.new(
        timeout_seconds: 5
      ),
      idempotency_policy: policy
    )

    action = JobSearch::AgentAction.new(
      tool: :submit_application,
      arguments: {
        job_id: "job-123"
      }
    )

    # 1. A API externa sofre timeout.
    expect {
  executor.execute(
    action,
    idempotency_key: key
  )
}.to raise_error(
  JobSearch::ToolTimeoutError
)

    operation = JobSearchOperation.find_by!(
      operation_key: key
    )

    expect(operation.status).to eq("uncertain")
    expect(operation.operation_type).to eq("apply_job")
    expect(executions).to eq(1)

    # 2. A operação não pode ser executada novamente.
    expect {
      executor.execute(
        action,
        idempotency_key: key
      )
    }.to raise_error(
      JobSearch::IdempotencyPolicy::OperationInProgress
    )

    expect(executions).to eq(1)

    # 3. O serviço externo confirma a candidatura.
    result = {
      "application_id" => 789,
      "status" => "submitted"
    }

    checker = double("ApplicationsReconciliationChecker")

    allow(checker).to receive(:call)
      .with(key: key)
      .and_return(
        status: :confirmed,
        result: result
      )

    reconciliation_registry =
      JobSearch::ReconciliationRegistry.new

    reconciliation_registry.register(
      :apply_job,
      checker
    )

    container = JobSearch::ReconciliationContainer.new(
      registry: reconciliation_registry,
      store: store
    )

    allow(JobSearch::ReconciliationContainer)
      .to receive(:configured)
      .and_return(container)

    # 4. O ActiveJob reconcilia a operação.
    JobSearch::ReconciliationJob.perform_now(key)

    operation.reload

    expect(operation.status).to eq("completed")
    expect(operation.result).to eq(result)
    expect(executions).to eq(1)

    # 5. Nova chamada reutiliza o resultado persistido.
    cached_result = executor.execute(
      action,
      idempotency_key: key
    )

    expect(cached_result).to eq(result)
    expect(executions).to eq(1)
  end
end

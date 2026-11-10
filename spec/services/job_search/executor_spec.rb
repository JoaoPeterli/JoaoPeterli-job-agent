require "rails_helper"

RSpec.describe JobSearch::Executor do
  let(:tool_class) do
    Class.new do
      def call(technology:, remote:)
        {

          technology: technology,

          remote: remote

        }
      end
    end
  end

  let(:registry) do
    registry = JobSearch::ToolRegistry.new

    registry.register(

      :search_jobs,

      tool_class

    )

    registry
  end

  let(:definition) do
    JobSearch::ToolDefinition.new(

      name: :search_jobs,

      description: "Search for jobs",

      schema: {

        technology: String,

        remote: [

          TrueClass,

          FalseClass

        ]

      },
      side_effects: false

    )
  end

  let(:catalog) do
    JobSearch::ToolCatalog.new(

      definitions: [

        definition

      ]

    )
  end

  let(:validator) do
    JobSearch::ToolValidator.new
  end

  let(:retry_policy) do
    JobSearch::RetryPolicy.new(

      max_attempts: 3,

      backoff_strategy: JobSearch::BackoffStrategy.new(

        base_delay: 0

      ),

      sleeper: JobSearch::Sleeper.new

    )
  end

  let(:execution_budget) do
    JobSearch::ExecutionBudget.new(

      max_steps: 10,

      max_tool_calls: 10

    )
  end

  let(:timeout_policy) do
    JobSearch::TimeoutPolicy.new(

      timeout_seconds: 5

    )
  end

  let(:executor) do
    described_class.new(

      registry: registry,

      retry_policy: retry_policy,

      tool_catalog: catalog,

      tool_validator: validator,

      execution_budget: execution_budget,

      timeout_policy: timeout_policy

    )
  end

  describe "#execute" do
    it "executes a valid action" do
      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby",

          remote: true

        }

      )

      result = executor.execute(

        action

      )

      expect(result).to eq(

        {

          technology: "Ruby",

          remote: true

        }

      )
    end

    it "rejects an action with a missing argument" do
      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby"

        }

      )

      expect {
        executor.execute(

          action

        )
      }.to raise_error(

        ArgumentError,

        "Missing argument: remote"

      )
    end

    it "rejects an action with an unknown argument" do
      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby",

          remote: true,

          salary: 20_000

        }

      )

      expect {
        executor.execute(

          action

        )
      }.to raise_error(

        ArgumentError,

        "Unknown argument: salary"

      )
    end

    it "rejects an action with an invalid argument type" do
      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby",

          remote: "yes"

        }

      )

      expect {
        executor.execute(

          action

        )
      }.to raise_error(

        ArgumentError,

        "Invalid type for argument: remote"

      )
    end

    it "reports execution attempts" do
      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby",

          remote: true

        }

      )

      attempts = []

      executor.execute(

        action,

        on_attempt: ->(attempt) {
          attempts << attempt
        }

      )

      expect(attempts).to eq(

        [ 1 ]

      )
    end

    it "consumes one tool call from the execution budget" do
      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby",

          remote: true

        }

      )

      executor.execute(

        action

      )

      expect(

        execution_budget.tool_calls

      ).to eq(

        1

      )
    end

    it "consumes a tool call for every retry attempt" do
      attempts = 0

      retrying_tool_class = Class.new do
        define_method(:call) do |technology:, remote:|
          attempts += 1

          if attempts < 3

            raise JobSearch::TransientError,

                  "Temporary failure"

          end

          {

            technology: technology,

            remote: remote

          }
        end
      end

      retry_registry = JobSearch::ToolRegistry.new

      retry_registry.register(

        :search_jobs,

        retrying_tool_class

      )

      retry_executor = described_class.new(

        registry: retry_registry,

        retry_policy: retry_policy,

        tool_catalog: catalog,

        tool_validator: validator,

        execution_budget: execution_budget,

        timeout_policy: timeout_policy

      )

      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby",

          remote: true

        }

      )

      result = retry_executor.execute(

        action

      )

      expect(attempts).to eq(

        3

      )

      expect(

        execution_budget.tool_calls

      ).to eq(

        3

      )

      expect(result).to eq(

        {

          technology: "Ruby",

          remote: true

        }

      )
    end

    it "stops execution when the tool call budget is exceeded" do
      executions = 0

      failing_tool_class = Class.new do
        define_method(:call) do |technology:, remote:|
          executions += 1

          raise JobSearch::TransientError,

                "Temporary failure"
        end
      end

      limited_registry = JobSearch::ToolRegistry.new

      limited_registry.register(

        :search_jobs,

        failing_tool_class

      )

      limited_budget = JobSearch::ExecutionBudget.new(

        max_steps: 10,

        max_tool_calls: 2

      )

      limited_executor = described_class.new(

        registry: limited_registry,

        retry_policy: retry_policy,

        tool_catalog: catalog,

        tool_validator: validator,

        execution_budget: limited_budget,

        timeout_policy: timeout_policy

      )

      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby",

          remote: true

        }

      )

      expect {
        limited_executor.execute(

          action

        )
      }.to raise_error(

    JobSearch::ExecutionBudgetExceeded,

        "Execution exceeds maximum number of tool calls: 3 > 2"

      )

      expect(

        executions

      ).to eq(

        2

      )

      expect(

        limited_budget.tool_calls

      ).to eq(

        3

      )
    end

    it "stops retrying when the execution deadline is exceeded" do
      executions = 0

      failing_tool_class = Class.new do
        define_method(:call) do |technology:, remote:|
          executions += 1

          raise JobSearch::TransientError,

                "Temporary failure"
        end
      end

      deadline_registry = JobSearch::ToolRegistry.new

      deadline_registry.register(

        :search_jobs,

        failing_tool_class

      )

      clock = instance_double(

    JobSearch::Clock

      )

      allow(clock).to receive(:now).and_return(

          100.0,

          105.0,

          111.0

        )

      deadline_budget = JobSearch::ExecutionBudget.new(

        max_steps: 10,

        max_tool_calls: 10,

        max_execution_seconds: 10,

        clock: clock

      )

      deadline_executor = described_class.new(

        registry: deadline_registry,

        retry_policy: retry_policy,

        tool_catalog: catalog,

        tool_validator: validator,

        execution_budget: deadline_budget,

        timeout_policy: timeout_policy

      )

      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby",

          remote: true

        }

      )

      expect {
        deadline_executor.execute(

          action

        )
      }.to raise_error(

    JobSearch::ExecutionBudgetExceeded,

        "Execution exceeds maximum execution time: 11.0 > 10"

      )

      expect(

        executions

      ).to eq(

        1

      )

      expect(

        deadline_budget.tool_calls

      ).to eq(

        1

      )
    end

    it "stops a tool when its execution exceeds the timeout" do
      executions = 0

      slow_tool_class = Class.new do
        define_method(:call) do |technology:, remote:|
          executions += 1

          sleep(0.05)

          {

            technology: technology,

            remote: remote

          }
        end
      end

      timeout_registry = JobSearch::ToolRegistry.new

      timeout_registry.register(

        :search_jobs,

        slow_tool_class

      )

      short_timeout_policy = JobSearch::TimeoutPolicy.new(

        timeout_seconds: 0.01

      )

      timeout_executor = described_class.new(

        registry: timeout_registry,

        retry_policy: retry_policy,

        tool_catalog: catalog,

        tool_validator: validator,

        execution_budget: execution_budget,

        timeout_policy: short_timeout_policy

      )

      action = JobSearch::AgentAction.new(

        tool: :search_jobs,

        arguments: {

          technology: "Ruby",

          remote: true

        }

      )

      expect {
        timeout_executor.execute(

          action

        )
      }.to raise_error(

    JobSearch::ToolTimeoutError,

        "Tool execution exceeded timeout of 0.01 seconds"

      )

      expect(

        executions

      ).to eq(

        1

      )

      expect(

        execution_budget.tool_calls

      ).to eq(

        1

      )
    end
  end


context "when idempotency is enabled" do
  let(:action) do
    JobSearch::AgentAction.new(
      tool: :search_jobs,
      arguments: {
        technology: "Ruby",
        remote: true
      }
    )
  end

  let(:idempotency_policy) do
    instance_double(JobSearch::IdempotencyPolicy)
  end

  let(:lease) do
    JobSearch::Lease.new(
      key: "operation-key",
      token: "lease-token",
      fencing_token: 1
    )
  end

  let(:executor_with_idempotency) do
    described_class.new(
      registry: registry,
      retry_policy: retry_policy,
      tool_catalog: catalog,
      tool_validator: validator,
      execution_budget: execution_budget,
      timeout_policy: timeout_policy,
      idempotency_policy: idempotency_policy
    )
  end


it "propagates the operation type for a side-effecting tool" do
  allow(definition)
    .to receive(:side_effects)
    .and_return(true)

  allow(definition)
    .to receive(:operation_type)
    .and_return("apply_job")

  expect(idempotency_policy)
    .to receive(:call)
    .with(
      key: "application-123",
      recover_expired: false,
      operation_type: "apply_job",
      side_effects: true
    )
    .and_yield(lease)

  result = executor_with_idempotency.execute(
    action,
    idempotency_key: "application-123"
  )

  expect(result).to eq(
    technology: "Ruby",
    remote: true
  )
end


  it "does not assign an operation type to a read-only tool" do
    expect(idempotency_policy)
      .to receive(:call)
      .with(
        key: "search-123",
        recover_expired: true,
        operation_type: nil,
        side_effects: false
      )
      .and_yield(lease)

    result = executor_with_idempotency.execute(
      action,
      idempotency_key: "search-123"
    )

    expect(result).to eq(
      technology: "Ruby",
      remote: true
    )
  end
end
end

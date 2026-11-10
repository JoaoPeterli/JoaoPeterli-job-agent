require "rails_helper"

RSpec.describe JobSearch::PlanningRetryPolicy do
  describe "#call" do
    let(:objective) do
      "Encontrar vagas Ruby"
    end

    it "returns the result when planning succeeds" do
      policy = described_class.new(
        max_attempts: 3
      )

      result = policy.call(
        objective: objective
      ) do |_context|
        :valid_plan
      end

      expect(result).to eq(
        :valid_plan
      )
    end

    it "provides the first planning context" do
      policy = described_class.new(
        max_attempts: 3
      )

      received_context = nil

      policy.call(
        objective: objective
      ) do |context|
        received_context = context

        :valid_plan
      end

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
    end

    it "retries with the previous planning error" do
      policy = described_class.new(
        max_attempts: 3
      )

      contexts = []

      result = policy.call(
        objective: objective
      ) do |context|
        contexts << context

        if context.attempt == 1
          raise JobSearch::PlanningError,
                "Invalid LLM plan"
        end

        :valid_plan
      end

      expect(result).to eq(
        :valid_plan
      )

      expect(contexts.length).to eq(
        2
      )

      expect(
        contexts[0].attempt
      ).to eq(
        1
      )

      expect(
        contexts[0].previous_error
      ).to be_nil

      expect(
        contexts[1].attempt
      ).to eq(
        2
      )

      expect(
        contexts[1].previous_error
      ).to be_a(
        JobSearch::PlanningError
      )
    end

    it "stops after reaching the maximum number of attempts" do
      policy = described_class.new(
        max_attempts: 3
      )

      contexts = []

      expect {
        policy.call(
          objective: objective
        ) do |context|
          contexts << context

          raise JobSearch::PlanningError,
                "Invalid LLM plan"
        end
      }.to raise_error(
        JobSearch::PlanningError,
        "Invalid LLM plan"
      )

      expect(
        contexts.map(&:attempt)
      ).to eq(
        [ 1, 2, 3 ]
      )
    end
  end


describe "retryable planning errors" do
  it "retries a recoverable planning error" do
    policy = described_class.new(max_attempts: 3)
    attempts = 0

    result = policy.call(objective: "Find Ruby jobs") do
      attempts += 1

      if attempts == 1
        raise JobSearch::PlanningError.new(
          "Invalid plan",
          retryable: true
        )
      end

      :success
    end

    expect(result).to eq(:success)
    expect(attempts).to eq(2)
  end

  it "does not retry a permanent planning error" do
    policy = described_class.new(max_attempts: 3)
    attempts = 0

    expect {
      policy.call(objective: "Find Ruby jobs") do
        attempts += 1

        raise JobSearch::PlanningError.new(
          "Invalid configuration",
          retryable: false
        )
      end
    }.to raise_error(
      JobSearch::PlanningError,
      "Invalid configuration"
    )

    expect(attempts).to eq(1)
  end

  it "rejects an invalid retry limit" do
    expect {
      described_class.new(max_attempts: 0)
    }.to raise_error(
      ArgumentError,
      "max_attempts must be positive"
    )
  end

  describe "planning history" do
    let(:objective) { "Encontrar vagas Ruby" }

    def rejected(message)
      JobSearch::PlanningError.new(
        "Invalid LLM plan",
        cause: JobSearch::PlanValidationError.new(message)
      )
    end

    it "records every rejected plan in the memory" do
      memory = JobSearch::ShortTermMemory.new
      policy = described_class.new(max_attempts: 3)
      errors = [ rejected("Unknown tool: foo"), rejected("Cycle detected") ]

      policy.call(objective: objective, memory: memory) do |_context|
        raise errors.shift if errors.any?

        :valid_plan
      end

      expect(memory.of_kind(:plan_rejected).map(&:content)).to eq([
        "Attempt 1: Unknown tool: foo",
        "Attempt 2: Cycle detected"
      ])
    end

    it "gives each attempt the rejections before the latest one" do
      policy = described_class.new(max_attempts: 3)
      errors = [ rejected("Unknown tool: foo"), rejected("Cycle detected") ]
      contexts = []

      policy.call(objective: objective) do |context|
        contexts << context
        raise errors.shift if errors.any?

        :valid_plan
      end

      expect(contexts.map(&:history)).to eq([
        [],
        [],
        [ "Attempt 1: Unknown tool: foo" ]
      ])
      expect(contexts.last.previous_error.cause.message).to eq("Cycle detected")
    end

    it "records the final rejection even when attempts are exhausted" do
      memory = JobSearch::ShortTermMemory.new
      policy = described_class.new(max_attempts: 1)

      expect do
        policy.call(objective: objective, memory: memory) do |_context|
          raise rejected("Unknown tool: foo")
        end
      end.to raise_error(JobSearch::PlanningError)

      expect(memory.of_kind(:plan_rejected).size).to eq(1)
    end

    it "does not record non-retryable errors as rejected plans" do
      memory = JobSearch::ShortTermMemory.new
      policy = described_class.new(max_attempts: 3)

      expect do
        policy.call(objective: objective, memory: memory) do |_context|
          raise JobSearch::PlanningError.new("LLM down", retryable: false)
        end
      end.to raise_error(JobSearch::PlanningError)

      expect(memory).to be_empty
    end
  end

  describe "lessons from previous runs" do
    it "passes the same lessons to every attempt" do
      policy = described_class.new(max_attempts: 2)
      contexts = []

      policy.call(objective: "Vagas Ruby", lessons: [ "Unknown tool: foo" ]) do |context|
        contexts << context
        if contexts.size == 1
          raise JobSearch::PlanningError.new(
            "Invalid LLM plan",
            cause: JobSearch::PlanValidationError.new("Cycle detected")
          )
        end

        :valid_plan
      end

      expect(contexts.map(&:lessons)).to eq([ [ "Unknown tool: foo" ], [ "Unknown tool: foo" ] ])
    end
  end
end
end

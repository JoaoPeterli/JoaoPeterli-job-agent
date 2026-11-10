require "rails_helper"

RSpec.describe JobSearch::ExecutionBudget do
  describe "#validate!" do
    it "allows a plan within the step limit" do
      plan = instance_double(
        JobSearch::Plan,
        steps: [
          double(:step),
          double(:step),
          double(:step)
        ]
      )

      budget = described_class.new(
        max_steps: 3
      )

      expect(
        budget.validate!(plan: plan)
      ).to eq(
        true
      )
    end

    it "rejects a plan that exceeds the step limit" do
      plan = instance_double(
        JobSearch::Plan,
        steps: [
          double(:step),
          double(:step),
          double(:step)
        ]
      )

      budget = described_class.new(
        max_steps: 2
      )

      expect {
        budget.validate!(
          plan: plan
        )
      }.to raise_error(
        JobSearch::ExecutionBudgetExceeded,
        "Plan exceeds maximum number of steps: 3 > 2"
      )
    end
  end

  describe "#consume_tool_call!" do
    it "allows tool calls within the limit" do
      budget = described_class.new(
        max_steps: 10,
        max_tool_calls: 3
      )

      expect(
        budget.consume_tool_call!
      ).to eq(
        1
      )

      expect(
        budget.consume_tool_call!
      ).to eq(
        2
      )

      expect(
        budget.consume_tool_call!
      ).to eq(
        3
      )
    end

    it "rejects a tool call when the limit is exceeded" do
      budget = described_class.new(
        max_steps: 10,
        max_tool_calls: 2
      )

      budget.consume_tool_call!
      budget.consume_tool_call!

      expect {
        budget.consume_tool_call!
      }.to raise_error(
        JobSearch::ExecutionBudgetExceeded,
        "Execution exceeds maximum number of tool calls: 3 > 2"
      )
    end
  end

  describe "#validate_execution_time!" do
    it "allows execution within the time limit" do
      clock = instance_double(
        JobSearch::Clock
      )

      allow(clock)
        .to receive(:now)
        .and_return(
          100.0,
          120.0
        )

      budget = described_class.new(
        max_steps: 10,
        max_execution_seconds: 30,
        clock: clock
      )

      expect(
        budget.validate_execution_time!
      ).to eq(
        true
      )
    end

    it "rejects execution when the time limit is exceeded" do
      clock = instance_double(
        JobSearch::Clock
      )

      allow(clock)
        .to receive(:now)
        .and_return(
          100.0,
          131.0
        )

      budget = described_class.new(
        max_steps: 10,
        max_execution_seconds: 30,
        clock: clock
      )

      expect {
        budget.validate_execution_time!
      }.to raise_error(
        JobSearch::ExecutionBudgetExceeded,
        "Execution exceeds maximum execution time: 31.0 > 30"
      )
    end
  end
end

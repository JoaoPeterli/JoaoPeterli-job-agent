require "rails_helper"

RSpec.describe JobSearch::TimeoutPolicy do
  describe "#call" do
    it "returns the result when execution finishes within the timeout" do
      policy = described_class.new(
        timeout_seconds: 1
      )

      result = policy.call do
        "completed"
      end

      expect(
        result
      ).to eq(
        "completed"
      )
    end

    it "raises a tool timeout error when execution exceeds the timeout" do
      policy = described_class.new(
        timeout_seconds: 0.01
      )

      expect {
        policy.call do
          sleep(0.05)
        end
      }.to raise_error(
        JobSearch::ToolTimeoutError,
        "Tool execution exceeded timeout of 0.01 seconds"
      )
    end
  end
end

require "rails_helper"

RSpec.describe JobSearch::ExecutionReport do
  describe "#to_h" do
    it "builds a report from the agent state" do
      state = JobSearch::AgentState.new(
        objective: "Encontrar vagas Ruby"
      )

      state.start_step!(:search)
      state.record_attempt(:search, 1)

      state.add_observation(
        :search,
        [
          {
            title: "Senior Ruby Developer"
          }
        ]
      )

      state.complete_step!(:search)
      state.complete!

      report = described_class.new(
        state: state
      )

      result = report.to_h

      expect(result[:objective])
        .to eq("Encontrar vagas Ruby")

      expect(result[:status])
        .to eq(:completed)

      expect(
        result[:steps][:search][:status]
      ).to eq(:completed)

      expect(
        result[:steps][:search][:attempts]
      ).to eq(1)

      expect(
        result[:steps][:search][:duration]
      ).to be_a(Numeric)

      expect(
        result[:steps][:search][:error]
      ).to be_nil
    end

    it "includes the error message for a failed step" do
      state = JobSearch::AgentState.new(
        objective: "Encontrar vagas Ruby"
      )

      error = StandardError.new(
        "API unavailable"
      )

      state.start_step!(:search)
      state.record_attempt(:search, 3)

      state.fail_step!(
        :search,
        error: error
      )

      state.failed!

      report = described_class.new(
        state: state
      )

      result = report.to_h

      expect(result[:status])
        .to eq(:failed)

      expect(
        result[:steps][:search][:status]
      ).to eq(:failed)

      expect(
        result[:steps][:search][:attempts]
      ).to eq(3)

      expect(
        result[:steps][:search][:error]
      ).to eq("API unavailable")
    end
  end
end

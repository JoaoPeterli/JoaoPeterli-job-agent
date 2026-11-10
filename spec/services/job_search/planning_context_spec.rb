require "rails_helper"

RSpec.describe JobSearch::PlanningContext do
  describe "#initialize" do
    it "stores the planning objective" do
      context = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      expect(
        context.objective
      ).to eq(
        "Encontrar vagas Ruby"
      )
    end

    it "starts with attempt one" do
      context = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      expect(
        context.attempt
      ).to eq(
        1
      )
    end

    it "starts without a previous error" do
      context = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      expect(
        context.previous_error
      ).to be_nil
    end

    it "can store a previous planning error" do
      error = JobSearch::PlanningError.new(
        "Invalid LLM plan"
      )

      context = described_class.new(
        objective: "Encontrar vagas Ruby",
        attempt: 2,
        previous_error: error
      )

      expect(
        context.attempt
      ).to eq(
        2
      )

      expect(
        context.previous_error
      ).to eq(
        error
      )
    end
  end
end

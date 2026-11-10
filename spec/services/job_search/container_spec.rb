require "rails_helper"

RSpec.describe JobSearch::Container do
  describe "#plan_executor" do
    it "builds the plan executor" do
      container = described_class.new

      expect(container.plan_executor)
        .to be_a(JobSearch::PlanExecutor)
    end
  end

  describe "#agent" do
    it "builds an agent for the objective" do
      container = described_class.new

      agent = container.agent(
        objective: "Encontrar vagas Ruby remotas"
      )

      expect(agent)
        .to be_a(JobSearch::Agent)

      expect(agent.objective)
        .to eq("Encontrar vagas Ruby remotas")
    end
  end
end

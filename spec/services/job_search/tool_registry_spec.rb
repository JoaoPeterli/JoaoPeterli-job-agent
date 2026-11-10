require "rails_helper"

RSpec.describe JobSearch::ToolRegistry do
  describe "#register and #fetch" do
    it "registers and retrieves a tool" do
      registry = described_class.new

      tool = Class.new

      registry.register(:search_jobs, tool)

      expect(
        registry.fetch(:search_jobs)
      ).to eq(tool)
    end
  end

  describe "#registered?" do
    it "returns true for a registered tool" do
        registry = described_class.new

        registry.register(
        :search_jobs,
        JobSearch::SearchJobsTool
        )

        expect(
        registry.registered?(:search_jobs)
        ).to be(true)
    end

    it "returns false for an unknown tool" do
        registry = described_class.new

        expect(
        registry.registered?(:hack_the_planet)
        ).to be(false)
    end
  end
end

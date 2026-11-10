
require "rails_helper"

RSpec.describe JobSearch::ToolDefinition do
  describe "execution safety" do
    it "defaults to side effects enabled" do
      definition = described_class.new(
        name: :apply_job,
        description: "Apply for a job"
      )

      expect(definition.side_effects).to be(true)
    end

    it "allows read-only tools" do
      definition = described_class.new(
        name: :search_jobs,
        description: "Search jobs",
        side_effects: false
      )

      expect(definition.side_effects).to be(false)
    end

    it "preserves the existing serialization" do
      definition = described_class.new(
        name: :search_jobs,
        description: "Search jobs",
        side_effects: false
      )

      expect(definition.to_h).to eq(
        name: :search_jobs,
        description: "Search jobs",
        arguments: {}
      )
    end
  end
end

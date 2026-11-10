require "rails_helper"

RSpec.describe JobSearch::PlanOutputSchema do
  describe "#to_h" do
    it "builds the plan schema from the tool catalog" do
      search_definition = JobSearch::ToolDefinition.new(
        name: :search_jobs,
        description: "Search for jobs",
        arguments: {
          technology: "Technology",
          remote: "Remote only"
        },
        schema: {
          technology: String,
          remote: [
            TrueClass,
            FalseClass
          ]
        }
      )

      catalog = JobSearch::ToolCatalog.new(
        definitions: [
          search_definition
        ]
      )

      schema = described_class.new(
        tool_catalog: catalog
      ).to_h

      expect(
        schema.dig(
          :properties,
          :steps,
          :items,
          :anyOf,
          0,
          :properties,
          :tool
        )
      ).to eq(
        {
          type: "string",
          const: "search_jobs"
        }
      )

      expect(
        schema.dig(
          :properties,
          :steps,
          :items,
          :anyOf,
          0,
          :properties,
          :arguments
        )
      ).to eq(
        search_definition.json_schema
      )
    end
  end
end

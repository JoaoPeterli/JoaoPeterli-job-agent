require "rails_helper"

RSpec.describe JobSearch::ToolCatalog do
  let(:search_definition) do
    JobSearch::ToolDefinition.new(
      name: :search_jobs,
      description: "Search for jobs",
      arguments: {
        technology: "String",
        remote: "Boolean"
      },
      schema: {
        technology: String,
        remote: [
          TrueClass,
          FalseClass
        ]
      }
    )
  end

  let(:profile_definition) do
    JobSearch::ToolDefinition.new(
      name: :candidate_profile,
      description: "Returns the candidate profile"
    )
  end

  let(:catalog) do
    described_class.new(
      definitions: [
        search_definition,
        profile_definition
      ]
    )
  end

  describe "#to_prompt" do
    it "describes the available tools" do
      prompt = catalog.to_prompt

      expect(prompt)
        .to include(
          "Tool: search_jobs"
        )

      expect(prompt)
        .to include(
          "technology"
        )

      expect(prompt)
        .to include(
          "Tool: candidate_profile"
        )
    end
  end

  describe "#fetch" do
    it "returns a definition by name" do
      expect(
        catalog.fetch(:search_jobs)
      ).to eq(
        search_definition
      )
    end

    it "raises when the definition does not exist" do
      expect {
        catalog.fetch(
          :hack_the_planet
        )
      }.to raise_error(
        KeyError,
        "Unknown tool definition: hack_the_planet"
      )
    end
  end

  describe "#json_schemas" do
  it "returns JSON schemas for all tool definitions" do
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

    profile_definition = JobSearch::ToolDefinition.new(
      name: :candidate_profile,
      description: "Returns candidate profile",
      arguments: {},
      schema: {}
    )

    catalog = described_class.new(
      definitions: [
        search_definition,
        profile_definition
      ]
    )

    expect(
      catalog.json_schemas
    ).to eq(
      {
        search_jobs: {
          type: "object",
          properties: {
            technology: {
              type: "string"
            },
            remote: {
              type: "boolean"
            }
          },
          required: [
            "technology",
            "remote"
          ],
          additionalProperties: false
        },

        candidate_profile: {
          type: "object",
          properties: {},
          required: [],
          additionalProperties: false
        }
      }
    )
  end
end
end

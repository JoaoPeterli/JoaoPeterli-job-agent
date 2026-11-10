require "rails_helper"

RSpec.describe JobSearch::ToolDefinition do
  describe "#to_h" do
    it "returns the tool definition" do
      definition = described_class.new(
        name: :search_jobs,
        description: "Search for jobs",
        arguments: {
          technology: "Technology to search",
          remote: "Whether the job must be remote"
        },
        schema: {
          technology: String,
          remote: [
            TrueClass,
            FalseClass
          ]
        }
      )

      expect(
        definition.to_h
      ).to eq(
        {
          name: :search_jobs,
          description: "Search for jobs",
          arguments: {
            technology: "Technology to search",
            remote: "Whether the job must be remote"
          }
        }
      )
    end
  end

  describe "#argument_schema" do
    it "returns the runtime argument schema" do
      definition = described_class.new(
        name: :search_jobs,
        description: "Search for jobs",
        arguments: {
          technology: "Technology to search",
          remote: "Whether the job must be remote"
        },
        schema: {
          technology: String,
          remote: [
            TrueClass,
            FalseClass
          ]
        }
      )

      expect(
        definition.argument_schema
      ).to eq(
        {
          technology: String,
          remote: [
            TrueClass,
            FalseClass
          ]
        }
      )
    end
  end

  describe "#json_schema" do
  it "builds JSON Schema from the argument schema" do
    definition = described_class.new(
      name: :search_jobs,
      description: "Search for jobs",
      arguments: {
        technology: "Technology to search",
        remote: "Whether the job must be remote"
      },
      schema: {
        technology: String,
        remote: [
          TrueClass,
          FalseClass
        ]
      }
    )

    expect(
      definition.json_schema
    ).to eq(
      {
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
      }
    )
  end
end
describe "#planning_schema" do
  it "returns a different schema for planning when provided" do
    definition = described_class.new(
      name: :analyze_jobs,
      description: "Analyze jobs",
      arguments: {
        jobs: "Jobs reference",
        profile: "Profile reference"
      },
      schema: {
        jobs: Array,
        profile: Hash
      },
      planning_schema: {
        jobs: JobSearch::ObservationReference,
        profile: JobSearch::ObservationReference
      }
    )

    expect(
      definition.argument_schema
    ).to eq(
      {
        jobs: Array,
        profile: Hash
      }
    )

    expect(
      definition.planning_schema
    ).to eq(
      {
        jobs: JobSearch::ObservationReference,
        profile: JobSearch::ObservationReference
      }
    )
  end

  it "uses the runtime schema for planning by default" do
    definition = described_class.new(
      name: :search_jobs,
      description: "Search jobs",
      schema: {
        technology: String
      }
    )

    expect(
      definition.planning_schema
    ).to eq(
      {
        technology: String
      }
    )
  end
end


describe "#operation_type" do
  it "stores an explicit reconciliation operation type" do
    definition = described_class.new(
      name: :submit_application,
      description: "Submit a job application",
      side_effects: true,
      operation_type: :apply_job
    )

    expect(definition.operation_type).to eq("apply_job")
  end

  it "defaults to nil for existing tool definitions" do
    definition = described_class.new(
      name: :search_jobs,
      description: "Search jobs",
      side_effects: false
    )

    expect(definition.operation_type).to be_nil
  end

  it "rejects an operation type on a read-only tool" do
    expect {
      described_class.new(
        name: :search_jobs,
        description: "Search jobs",
        side_effects: false,
        operation_type: :apply_job
      )
    }.to raise_error(
      ArgumentError,
      "Read-only tools cannot have an operation_type"
    )
  end
end
end

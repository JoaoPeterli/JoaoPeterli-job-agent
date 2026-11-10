require "rails_helper"

RSpec.describe JobSearch::JsonSchemaBuilder do
  describe "#build" do
    it "converts Ruby types into JSON Schema" do
      builder = described_class.new

      schema = builder.build(
        {
          technology: String,
          remote: [
            TrueClass,
            FalseClass
          ]
        }
      )

      expect(
        schema
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

    it "converts collection types into JSON Schema" do
  builder = described_class.new

  schema = builder.build(
    {
      jobs: Array,
      profile: Hash
    }
  )

  expect(
    schema
  ).to eq(
    {
      type: "object",
      properties: {
        jobs: {
          type: "array"
        },
        profile: {
          type: "object"
        }
      },
      required: [
        "jobs",
        "profile"
      ],
      additionalProperties: false
    }
  )
end
it "converts observation references into JSON Schema" do
  builder = described_class.new

  schema = builder.build(
    {
      jobs: JobSearch::ObservationReference
    }
  )

  expect(
    schema
  ).to eq(
    {
      type: "object",

      properties: {
        jobs: {
          type: "object",

          properties: {
            "$ref": {
              type: "string"
            }
          },

          required: [
            "$ref"
          ],

          additionalProperties: false
        }
      },

      required: [
        "jobs"
      ],

      additionalProperties: false
    }
  )
end
  end
end

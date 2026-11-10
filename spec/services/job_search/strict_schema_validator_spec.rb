require "rails_helper"

RSpec.describe JobSearch::StrictSchemaValidator do
  subject(:validator) { described_class.new }

  let(:valid_schema) do
    {
      type: "object",
      properties: {
        steps: {
          type: "array",
          items: {
            anyOf: [
              {
                type: "object",
                properties: { name: { type: "string" } },
                required: [ "name" ],
                additionalProperties: false
              }
            ]
          }
        }
      },
      required: [ "steps" ],
      additionalProperties: false
    }
  end

  it "accepts a strict-compatible schema" do
    expect(validator.validate!(valid_schema)).to be(true)
  end

  it "requires an object at the root" do
    expect { validator.validate!({ anyOf: [ valid_schema ] }) }
      .to raise_error(ArgumentError, /root must be an object/)
  end

  it "rejects objects that allow additional properties" do
    schema = valid_schema.deep_dup
    schema[:properties][:steps][:items][:anyOf][0][:additionalProperties] = true

    expect { validator.validate!(schema) }
      .to raise_error(ArgumentError, /\$\.steps\[\]\.anyOf\[0\] must set additionalProperties: false/)
  end

  it "rejects optional properties" do
    schema = valid_schema.deep_dup
    schema[:properties][:extra] = { type: "string" }

    expect { validator.validate!(schema) }
      .to raise_error(ArgumentError, /must require every property \(missing: extra\)/)
  end

  it "rejects a free-form object argument" do
    schema = valid_schema.deep_dup
    schema[:properties][:filters] = { type: "object" }
    schema[:required] << "filters"

    expect { validator.validate!(schema) }
      .to raise_error(ArgumentError, /\$\.filters must set additionalProperties: false/)
  end

  it "accepts string keys" do
    expect(validator.validate!(valid_schema.deep_stringify_keys)).to be(true)
  end

  it "accepts the plan schema generated for the application tools" do
    schema = JobSearch::Container.new.send(:plan_output_schema)

    expect(validator.validate!(schema)).to be(true)
  end
end

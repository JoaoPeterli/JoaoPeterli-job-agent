require "rails_helper"

RSpec.describe JobSearch::PlanOutputValidator do
  describe "#validate!" do
    let(:validator) do
      described_class.new
    end

    it "accepts a valid plan output" do
      data = {
        steps: [
          {
            name: "search",
            tool: "search_jobs",
            arguments: {
              technology: "Ruby",
              remote: true
            },
            dependencies: []
          }
        ]
      }

      expect {
        validator.validate!(data)
      }.not_to raise_error
    end

    it "rejects a non-hash root" do
      expect {
        validator.validate!([])
      }.to raise_error(
        ArgumentError,
        "Plan output must be an object"
      )
    end

    it "rejects output without steps" do
      expect {
        validator.validate!({})
      }.to raise_error(
        ArgumentError,
        "Plan output must contain steps"
      )
    end

    it "rejects steps that are not an array" do
      expect {
        validator.validate!(
          steps: "invalid"
        )
      }.to raise_error(
        ArgumentError,
        "Steps must be an array"
      )
    end

    it "rejects invalid step structures" do
      data = {
        steps: [
          {
            name: "search"
          }
        ]
      }

      expect {
        validator.validate!(data)
      }.to raise_error(
        ArgumentError,
        "Invalid step structure"
      )
    end


describe "step field types" do
  let(:valid_step) do
    {
      name: "search",
      tool: "search_jobs",
      arguments: {},
      dependencies: []
    }
  end

  {
    name: 123,
    tool: nil,
    arguments: "invalid",
    dependencies: "invalid"
  }.each do |field, invalid_value|
    it "rejects an invalid #{field} type" do
      step = valid_step.merge(
        field => invalid_value
      )

      expect {
        validator.validate!(
          steps: [ step ]
        )
      }.to raise_error(
        ArgumentError,
        /Invalid #{field}/
      )
    end
  end
end
  end

describe "semantic field validation" do
  let(:validator) do
    JobSearch::PlanOutputValidator.new
  end

  let(:valid_step) do
    {
      name: "search",
      tool: "search_jobs",
      arguments: {},
      dependencies: []
    }
  end

  it "rejects an empty step name" do
    step = valid_step.merge(
      name: ""
    )

    expect {
      validator.validate!(
        steps: [ step ]
      )
    }.to raise_error(
      JobSearch::PlanValidationError,
      "Invalid name: cannot be blank"
    )
  end

  it "rejects non-string dependencies" do
    step = valid_step.merge(
      dependencies: [ 123 ]
    )

    expect {
      validator.validate!(
        steps: [ step ]
      )
    }.to raise_error(
      JobSearch::PlanValidationError,
      "Invalid dependency: expected non-empty String"
    )
  end
end
end

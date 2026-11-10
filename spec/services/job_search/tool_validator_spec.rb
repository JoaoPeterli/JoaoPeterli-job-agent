require "rails_helper"

RSpec.describe JobSearch::ToolValidator do
  describe "#validate!" do
    let(:validator) do
      described_class.new
    end

    let(:schema) do
      {
        technology: String,
        remote: [ TrueClass, FalseClass ]
      }
    end

    it "accepts valid arguments" do
      arguments = {
        technology: "Ruby",
        remote: true
      }

      expect {
        validator.validate!(
          arguments: arguments,
          schema: schema
        )
      }.not_to raise_error
    end

    it "rejects missing arguments" do
      arguments = {
        technology: "Ruby"
      }

      expect {
        validator.validate!(
          arguments: arguments,
          schema: schema
        )
      }.to raise_error(
        ArgumentError,
        "Missing argument: remote"
      )
    end

    it "rejects unknown arguments" do
      arguments = {
        technology: "Ruby",
        remote: true,
        salary: 20_000
      }

      expect {
        validator.validate!(
          arguments: arguments,
          schema: schema
        )
      }.to raise_error(
        ArgumentError,
        "Unknown argument: salary"
      )
    end

    it "rejects arguments with invalid types" do
      arguments = {
        technology: "Ruby",
        remote: "yes"
      }

      expect {
        validator.validate!(
          arguments: arguments,
          schema: schema
        )
      }.to raise_error(
        ArgumentError,
        "Invalid type for argument: remote"
      )
    end
  end
end

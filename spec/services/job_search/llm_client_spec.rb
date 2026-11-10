require "rails_helper"

RSpec.describe JobSearch::LlmClient do
  describe "#complete" do
    it "requires an implementation" do
      client = described_class.new

      expect {
        client.complete(
          prompt: "Create a plan"
        )
      }.to raise_error(
        NotImplementedError,
        "Subclasses must implement #complete"
      )
    end
  end
end

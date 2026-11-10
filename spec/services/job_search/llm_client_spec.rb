require "rails_helper"

RSpec.describe JobSearch::LlmClient do
  describe "#generate" do
    it "requires an implementation" do
      expect { described_class.new.generate(prompt: "Create a plan") }
        .to raise_error(NotImplementedError, "Subclasses must implement #generate")
    end
  end

  describe "#complete" do
    let(:client_class) do
      Class.new(described_class) do
        def initialize(response)
          @response = response
        end

        def generate(prompt:)
          @response
        end
      end
    end

    it "returns the text of a usable response" do
      client = client_class.new(JobSearch::LlmResponse.new(text: '{"steps":[]}'))

      expect(client.complete(prompt: "Create a plan")).to eq('{"steps":[]}')
    end

    it "applies the response contract" do
      client = client_class.new(JobSearch::LlmResponse.new(text: "", refusal: "No."))

      expect { client.complete(prompt: "Create a plan") }.to raise_error(JobSearch::LlmRefusalError)
    end
  end
end

require "rails_helper"

RSpec.describe JobSearch::OpenAiLlmClient do
  describe "#complete" do
    it "sends the prompt using structured output" do
      response = instance_double(
        "OpenAIResponse",
        output_text: '{"steps":[]}'
      )

      responses_api = double(
        "ResponsesAPI"
      )

      client = double(
        "OpenAIClient",
        responses: responses_api
      )

      allow(responses_api)
        .to receive(:create)
        .and_return(response)

      output_schema = {
        type: "object",
        properties: {
          steps: {
            type: "array"
          }
        },
        required: [
          "steps"
        ],
        additionalProperties: false
      }

      llm_client = described_class.new(
        client: client,
        model: "test-model",
        output_schema: output_schema
      )

      result = llm_client.complete(
        prompt: "Create a plan"
      )

      expect(responses_api)
        .to have_received(:create)
        .with(
          model: "test-model",
          input: "Create a plan",
          text: {
            format: {
              type: :json_schema,
              name: "job_search_plan",
              strict: true,
              schema: output_schema
            }
          }
        )

      expect(result).to eq(
        '{"steps":[]}'
      )
    end

    it "sends max_output_tokens when configured" do
      responses_api = double("ResponsesAPI")
      allow(responses_api).to receive(:create)
        .and_return(instance_double("OpenAIResponse", output_text: "{}"))

      llm_client = described_class.new(
        client: double("OpenAIClient", responses: responses_api),
        model: "test-model",
        output_schema: {},
        max_output_tokens: 2_000
      )

      llm_client.complete(prompt: "Create a plan")

      expect(responses_api).to have_received(:create)
        .with(hash_including(max_output_tokens: 2_000))
    end
  end
end

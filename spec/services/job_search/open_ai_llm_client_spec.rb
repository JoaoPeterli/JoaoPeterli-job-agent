require "rails_helper"

RSpec.describe JobSearch::OpenAiLlmClient do
  let(:responses_api) { double("ResponsesAPI") }
  let(:client) { double("OpenAIClient", responses: responses_api) }

  let(:output_schema) do
    {
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
  end

  def fake_response(
    output_text: '{"steps":[]}',
    status: "completed",
    output: [],
    incomplete_reason: nil,
    usage: nil
  )
    double(
      "OpenAIResponse",
      output_text: output_text,
      status: status && status.to_sym,
      output: output,
      incomplete_details: incomplete_reason && double(reason: incomplete_reason),
      usage: usage
    )
  end

  def build_client(**options)
    described_class.new(
      client: client,
      model: "test-model",
      output_schema: output_schema,
      **options
    )
  end

  describe "#complete" do
    it "sends the prompt using structured output" do
      allow(responses_api).to receive(:create).and_return(fake_response)

      result = build_client.complete(prompt: "Create a plan")

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

      expect(result).to eq('{"steps":[]}')
    end

    it "sends max_output_tokens when configured" do
      allow(responses_api).to receive(:create).and_return(fake_response)

      build_client(max_output_tokens: 2_000).complete(prompt: "Create a plan")

      expect(responses_api).to have_received(:create)
        .with(hash_including(max_output_tokens: 2_000))
    end

    it "raises a non-retryable error when the model refuses" do
      refusal = double(type: :refusal, refusal: "I can't help with that.")
      message = double(type: :message, content: [ refusal ])
      allow(responses_api).to receive(:create)
        .and_return(fake_response(output_text: "", output: [ message ]))

      expect { build_client.complete(prompt: "Create a plan") }
        .to raise_error(JobSearch::LlmRefusalError, /I can't help with that/) { |error|
          expect(error).not_to be_retryable
        }
    end

    it "raises a retryable error when the response is truncated by max_output_tokens" do
      allow(responses_api).to receive(:create).and_return(
        fake_response(output_text: '{"steps":[{"na', status: "incomplete",
                      incomplete_reason: :max_output_tokens)
      )

      expect { build_client.complete(prompt: "Create a plan") }
        .to raise_error(JobSearch::LlmIncompleteResponseError, /smaller plan/) { |error|
          expect(error).to be_retryable
        }
    end
  end

  describe "#generate" do
    it "normalizes the provider response including token usage" do
      usage = double(input_tokens: 120, output_tokens: 30, total_tokens: 150)
      allow(responses_api).to receive(:create).and_return(fake_response(usage: usage))

      response = build_client.generate(prompt: "Create a plan")

      expect(response).to eq(
        JobSearch::LlmResponse.new(
          text: '{"steps":[]}',
          status: :completed,
          usage: JobSearch::LlmUsage.new(input_tokens: 120, output_tokens: 30, total_tokens: 150)
        )
      )
    end
  end

  describe "schema validation" do
    it "rejects a schema that is not compatible with strict mode at construction" do
      invalid_schema = output_schema.merge(additionalProperties: true)

      expect do
        described_class.new(client: client, model: "test-model", output_schema: invalid_schema)
      end.to raise_error(ArgumentError, /additionalProperties: false/)
    end
  end

  describe "provider errors" do
    def openai_error(klass, status)
      klass.new(
        url: URI("https://api.openai.com/v1/responses"), status: status,
        headers: {}, body: nil, request: nil, response: nil, message: "provider said no"
      )
    end

    {
      OpenAI::Errors::AuthenticationError => [ 401, false, /rejected the credentials \(HTTP 401\)/ ],
      OpenAI::Errors::PermissionDeniedError => [ 403, false, /rejected the credentials \(HTTP 403\)/ ],
      OpenAI::Errors::RateLimitError => [ 429, true, /unavailable \(RateLimitError\)/ ],
      OpenAI::Errors::InternalServerError => [ 500, true, /unavailable \(InternalServerError\)/ ],
      OpenAI::Errors::BadRequestError => [ 400, false, /rejected the request \(HTTP 400\)/ ]
    }.each do |error_class, (status, transient, message)|
      it "maps #{error_class.name.demodulize} to a non-retryable provider error" do
        allow(responses_api).to receive(:create).and_raise(openai_error(error_class, status))

        expect { build_client.complete(prompt: "Create a plan") }
          .to raise_error(JobSearch::LlmProviderError, message) { |error|
            expect(error).not_to be_retryable
            expect(error.transient?).to be(transient)
          }
      end
    end

    it "maps connection failures to a transient provider error" do
      allow(responses_api).to receive(:create)
        .and_raise(OpenAI::Errors::APIConnectionError.new(url: URI("https://api.openai.com")))

      expect { build_client.complete(prompt: "Create a plan") }
        .to raise_error(JobSearch::LlmProviderError) { |error| expect(error.transient?).to be(true) }
    end

    it "does not leak the provider message or the API key" do
      allow(responses_api).to receive(:create)
        .and_raise(openai_error(OpenAI::Errors::AuthenticationError, 401))

      expect { build_client.complete(prompt: "Create a plan") }
        .to raise_error(JobSearch::LlmProviderError) { |error|
          expect(error.message).not_to include("provider said no")
        }
    end

    it "is not recorded as a rejected plan" do
      allow(responses_api).to receive(:create)
        .and_raise(openai_error(OpenAI::Errors::AuthenticationError, 401))
      memory = JobSearch::ShortTermMemory.new
      policy = JobSearch::PlanningRetryPolicy.new(max_attempts: 3)
      calls = 0

      expect do
        policy.call(objective: "Vagas Ruby", memory: memory) do
          calls += 1
          build_client.complete(prompt: "Create a plan")
        end
      end.to raise_error(JobSearch::LlmProviderError)

      expect(calls).to eq(1)
      expect(memory).to be_empty
    end
  end
end

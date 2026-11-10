require "rails_helper"
require Rails.root.join("spec/support/job_search/security_helpers")

RSpec.describe "Security: secrets never leak" do
  include JobSearch::SecurityHelpers

  let(:secret) { "sk-test-DO-NOT-LEAK-123456" }

  it "does not repeat the provider's error message, which may contain the key" do
    responses_api = double("ResponsesAPI")
    allow(responses_api).to receive(:create).and_raise(
      OpenAI::Errors::AuthenticationError.new(
        url: URI("https://api.openai.com/v1/responses"), status: 401, headers: {}, body: nil,
        request: nil, response: nil, message: "Incorrect API key provided: #{secret}"
      )
    )
    client = JobSearch::OpenAiLlmClient.new(
      client: double(responses: responses_api), model: "m",
      output_schema: { type: "object", properties: {}, required: [], additionalProperties: false }
    )

    expect { client.complete(prompt: "p") }.to raise_error(JobSearch::LlmProviderError) { |error|
      expect(error.message).not_to include(secret)
      expect(error.message).to include("Check OPENAI_API_KEY")
    }
  end

  it "keeps a provider failure out of logs and audit trail details" do
    failure = JobSearch::LlmProviderError.new("provider down", transient: true)
    agent, = build_secured_agent("Encontrar vagas Ruby", [ failure ])

    expect { agent.run }.to raise_error(JobSearch::LlmProviderError)

    expect(AgentAuditEvent.last.details).to eq(
      "status" => "failed", "error_class" => "JobSearch::LlmProviderError"
    )
  end

  it "filters secret-looking keys in logs and audit details" do
    security_events.event_logger.info(event: "test", api_key: secret, nested: { session_token: secret })
    event = JobSearch::AuditTrail.new.record(
      run_id: "r", event: "test", outcome: "info", details: { client_secret: secret, password: secret }
    )

    expect(security_events.raw).not_to include(secret)
    expect(event.reload.details.to_json).not_to include(secret)
  end

  it "keeps the API key out of the codebase" do
    tracked = `git -C #{Rails.root} ls-files`.split("\n")

    expect(tracked).not_to include("config/master.key")
    offenders = tracked.reject { |path| path.start_with?("spec/") }.select do |path|
      file = Rails.root.join(path)
      File.file?(file) && File.read(file, encoding: "BINARY").match?(/sk-(proj-)?[A-Za-z0-9_-]{20,}/n)
    end
    expect(offenders).to be_empty
  end
end

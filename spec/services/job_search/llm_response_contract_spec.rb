require "rails_helper"

RSpec.describe JobSearch::LlmResponseContract do
  subject(:contract) { described_class.new }

  def response(**attributes)
    JobSearch::LlmResponse.new(text: '{"steps":[]}', **attributes)
  end

  it "returns the text of a completed response" do
    expect(contract.text!(response)).to eq('{"steps":[]}')
  end

  it "treats a response without status as completed" do
    expect(contract.text!(response(status: nil))).to eq('{"steps":[]}')
  end

  it "rejects a refusal without retrying" do
    expect { contract.text!(response(text: "", refusal: "No.")) }
      .to raise_error(JobSearch::LlmRefusalError, "LLM refused to plan: No.") { |error|
        expect(error).not_to be_retryable
      }
  end

  it "truncates a long refusal message" do
    expect { contract.text!(response(refusal: "x" * 1_000)) }
      .to raise_error(JobSearch::LlmRefusalError) { |error|
        expect(error.message.length).to be <= 250
      }
  end

  it "asks for a smaller plan when truncated by max_output_tokens" do
    truncated = response(status: :incomplete, incomplete_reason: :max_output_tokens)

    expect { contract.text!(truncated) }
      .to raise_error(JobSearch::LlmIncompleteResponseError, /smaller plan/) { |error|
        expect(error).to be_retryable
      }
  end

  it "does not retry other incomplete reasons" do
    filtered = response(status: :incomplete, incomplete_reason: :content_filter)

    expect { contract.text!(filtered) }
      .to raise_error(JobSearch::LlmIncompleteResponseError, /content_filter/) { |error|
        expect(error).not_to be_retryable
      }
  end

  it "rejects a failed response" do
    expect { contract.text!(response(status: :failed)) }
      .to raise_error(JobSearch::LlmResponseError, "LLM response failed")
  end

  it "rejects an empty response" do
    expect { contract.text!(response(text: "  ")) }
      .to raise_error(JobSearch::LlmResponseError, "LLM returned an empty response")
  end

  it "makes the truncation reason reach the next planning attempt" do
    policy = JobSearch::PlanningRetryPolicy.new(max_attempts: 2)
    contexts = []

    policy.call(objective: "Vagas Ruby") do |context|
      contexts << context
      if contexts.size == 1
        contract.text!(response(status: :incomplete, incomplete_reason: :max_output_tokens))
      end

      :plan
    end

    expect(contexts.last.previous_error.message).to include("smaller plan")
  end
end

require "rails_helper"

RSpec.describe JobSearch::Reflector do
  let(:llm) do
    Class.new do
      attr_reader :prompts
      attr_accessor :response

      def initialize = @prompts = []

      def complete(prompt:)
        @prompts << prompt
        response
      end
    end.new
  end

  def observation(iteration: 1, strong: 0, top: [ { title: "Rails Dev", score: 40 } ])
    JobSearch::IterationObservation.new(iteration: iteration, searches: [ { technology: "Ruby on Rails", remote: true } ],
                                        jobs_found: top.size, strong_matches: strong, top_jobs: top)
  end

  # reflect(decision: ..., reason: ...) ou reflect({}, obs: ...).
  def reflect(raw = nil, obs: observation, history: [], **json)
    llm.response = (raw || json).to_json
    described_class.new(llm_client: llm).reflect(objective: "Vagas Rails sênior", observation: obs, history: history)
  end

  it "finishes by rule, without the LLM, at the iteration limit or with enough strong matches" do
    expect(reflect({}, obs: observation(iteration: 3))).to have_attributes(decision: "finish", by: "rule")
    expect(reflect({}, obs: observation(strong: 5))).to have_attributes(decision: "finish", by: "rule", reason: /5 vagas fortes/)
    many = Array.new(15) { |i| { title: "Elixir #{i}", score: 30 } }
    expect(reflect({}, obs: observation(top: many))).to have_attributes(decision: "finish", by: "rule", reason: /15 vagas encontradas/)
    expect(llm.prompts).to be_empty
  end

  it "asks the LLM otherwise and returns its validated decision" do
    result = reflect(decision: "search_again", reason: "Só uma vaga fraca.", guidance: "Search \"Ruby\" remote instead.")

    expect(result).to have_attributes(decision: "search_again", reason: "Só uma vaga fraca.",
                                      guidance: "Search \"Ruby\" remote instead.", by: "llm")
    prompt = llm.prompts.sole
    expect(prompt).to include('Iteration 1: searched "Ruby on Rails" (remote); 1 jobs found, 0 strong matches')
    expect(prompt).to include('<untrusted_input source="job_boards">', "- Rails Dev (score 40)", "Never suggest a search that was already tried")
    expect(prompt).to include("low scores alone are not a reason")
  end

  it "includes the earlier iterations so it does not repeat them" do
    reflect({ decision: "finish", reason: "ok", guidance: "" }, obs: observation(iteration: 2), history: [ observation ])

    expect(llm.prompts.sole.scan("searched \"Ruby on Rails\"").size).to eq(2)
  end

  it "treats search_again without guidance as finish, and caps the guidance" do
    expect(reflect(decision: "search_again", reason: "x", guidance: "  ").decision).to eq("finish")
    expect(reflect(decision: "search_again", reason: "x", guidance: "a" * 500).guidance.length)
      .to eq(described_class::MAX_GUIDANCE_LENGTH)
  end

  it "rejects invalid output" do
    expect { reflect(decision: "delete_everything", reason: "x", guidance: "") }.to raise_error(JobSearch::ReflectionError)
    llm.response = "nope"
    expect { described_class.new(llm_client: llm).reflect(objective: "x", observation: observation) }
      .to raise_error(JobSearch::ReflectionError)
  end

  it "declares a strict schema" do
    expect { JobSearch::StrictSchemaValidator.new.validate!(described_class::SCHEMA) }.not_to raise_error
  end
end

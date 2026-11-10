require "rails_helper"

RSpec.describe JobSearch::ApplicationProposer do
  let(:audit_trail) { instance_double(JobSearch::AuditTrail, record: nil) }
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

  def run_with(jobs)
    AgentRun.create!(mode: "agent", objective: "x", idempotency_key: SecureRandom.uuid, status: "completed", result: { "output" => jobs })
  end

  let(:jobs) do
    [
      { "title" => "Senior Rails", "company" => "A", "score" => 95, "score_reason" => "Rails sênior remoto", "url" => "https://a.com/1" },
      { "title" => "Ruby Lead", "company" => "B", "score" => 80 },
      { "title" => "Java Dev", "company" => "C", "score" => 90 },
      { "title" => "Go Dev", "company" => "D", "score" => 85 },
      { "title" => "Low Fit", "company" => "E", "score" => 60 }
    ]
  end

  it "proposes up to 3 jobs with score >= 75, skipping disliked and already proposed ones, with LLM drafts" do
    JobFeedback.toggle!(jobs[2], verdict: "dislike")
    JobApplication.create!(run_id: SecureRandom.uuid, job_key: JobFeedback.key_for(jobs[3]), title: "Go Dev", message: "old")
    llm.response = { drafts: [ { id: 0, message: "Rascunho para Senior Rails" }, { id: 1, message: "Rascunho para Ruby Lead" } ] }.to_json
    run = run_with(jobs)

    proposals = described_class.new(llm_client: llm, audit_trail: audit_trail).propose(run)

    expect(proposals.map { |p| [ p.title, p.status, p.message ] }).to eq([
      [ "Senior Rails", "proposed", "Rascunho para Senior Rails" ], [ "Ruby Lead", "proposed", "Rascunho para Ruby Lead" ]
    ])
    expect(proposals.first).to have_attributes(run_id: run.id, score: 95, score_reason: "Rails sênior remoto", url: "https://a.com/1")
    expect(audit_trail).to have_received(:record).with(hash_including(event: "application.proposed")).twice
    expect(llm.prompts.sole).to include('<untrusted_input source="job_boards">', "never invent experience")
  end

  it "uses a template when the LLM fails, and proposes nothing twice" do
    llm.response = "not json"
    run = run_with(jobs.first(1))

    proposal = described_class.new(llm_client: llm, audit_trail: audit_trail).propose(run).sole

    expect(proposal.message).to include("Olá! Tenho interesse na vaga de Senior Rails na A")
    expect(described_class.new(llm_client: llm, audit_trail: audit_trail).propose(run)).to eq([])
  end

  it "proposes nothing below the minimum score" do
    expect(described_class.new(audit_trail: audit_trail).propose(run_with([ jobs.last ]))).to eq([])
  end
end

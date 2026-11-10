require "rails_helper"
require Rails.root.join("spec/support/job_search/security_helpers")

RSpec.describe "Agent audit trail" do
  include JobSearch::SecurityHelpers

  def fixture(name)
    File.read(Rails.root.join("spec/fixtures/llm/plans", name))
  end

  it "records every decision of a successful run in a valid chain" do
    agent, _llm, audit_trail = build_secured_agent("Encontrar vagas Ruby remotas", [ fixture("valid_full_plan.json") ])

    state = agent.run

    expect(audit_summary(audit_trail, state.run_id)).to eq([
      %w[run.started info],
      %w[plan.authorization allowed],
      %w[tool.authorization allowed],
      %w[tool.authorization allowed],
      %w[tool.authorization allowed],
      %w[run.finished completed]
    ])
    expect(audit_trail.events(state.run_id).map { |event| event.details["tool"] }.compact)
      .to eq(%w[search_jobs candidate_profile analyze_jobs])
    expect(audit_trail.verify(state.run_id)).to be_valid
  end

  it "records the objective digest, not the objective" do
    objective = "Encontrar vagas Ruby remotas"
    agent, _llm, audit_trail = build_secured_agent(objective, [ fixture("valid_search_only.json") ])

    state = agent.run

    started = audit_trail.events(state.run_id).first
    expect(started.details).to eq(
      "agent" => "job_search",
      "objective_sha256" => Digest::SHA256.hexdigest(objective), "objective_chars" => objective.length
    )
    expect(AgentAuditEvent.pluck(:details).to_json).not_to include(objective)
  end

  it "does not start the run when the audit trail is unavailable" do
    agent, llm_client, audit_trail = build_secured_agent("Encontrar vagas Ruby", [ fixture("valid_search_only.json") ])
    allow(audit_trail).to receive(:record).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect { agent.run }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    expect(llm_client.calls).to eq(0)
  end

  it "keeps the original error when only the final audit record fails" do
    agent, _llm, audit_trail = build_secured_agent("Encontrar vagas Ruby", [ JobSearch::LlmRefusalError.new("no") ])
    allow(audit_trail).to receive(:record).and_call_original
    allow(audit_trail).to receive(:record).with(hash_including(event: "run.finished"))
                                          .and_raise(ActiveRecord::ConnectionNotEstablished)

    expect { agent.run }.to raise_error(JobSearch::LlmRefusalError)
    expect(security_events.all.map { |event| event["event"] }).to include("agent_audit.record_failed")
  end
end

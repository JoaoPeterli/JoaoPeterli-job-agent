require "rails_helper"
require Rails.root.join("spec/support/job_search/security_helpers")

# Corpus de ataques conhecidos no objetivo: todos precisam ser barrados
# sem chamar o LLM e deixar registro na auditoria.
RSpec.describe "Security: prompt injection in the objective" do
  include JobSearch::SecurityHelpers

  attempts = YAML.safe_load_file(Rails.root.join("spec/fixtures/security/injection_attempts.yml"))

  attempts.each do |attempt|
    it "rejects #{attempt['name']} before calling the LLM" do
      agent, llm_client, audit_trail = build_secured_agent(attempt["text"], [])

      expect { agent.run }.to raise_error(JobSearch::UntrustedInputError) { |error|
        expect(error.signals).not_to be_empty
      }
      expect(llm_client.calls).to eq(0)

      run_id = last_run_id
      expect(audit_summary(audit_trail, run_id)).to eq([ %w[run.started info], %w[run.finished failed] ])
      expect(audit_trail.events(run_id).last.details).to include(
        "error_class" => "JobSearch::UntrustedInputError", "signals" => be_present
      )
      expect(audit_trail.verify(run_id)).to be_valid
    end
  end

  it "never stores the attack text in logs or in the audit trail" do
    text = attempts.first["text"]
    agent, = build_secured_agent(text, [])

    expect { agent.run }.to raise_error(JobSearch::UntrustedInputError)

    expect(security_events.raw).not_to include(text)
    expect(AgentAuditEvent.pluck(:details).to_json).not_to include("Ignore all previous")
  end
end

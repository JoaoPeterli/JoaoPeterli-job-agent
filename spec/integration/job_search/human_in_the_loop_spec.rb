require "rails_helper"

# Humano no laço, de ponta a ponta com o Container real: a apply_job só roda
# com a aprovação humana da AÇÃO EXATA, e tudo fica na trilha de auditoria.
RSpec.describe "Human in the loop: approved applications" do
  let(:run) { AgentRun.create!(mode: "agent", objective: "x", idempotency_key: SecureRandom.uuid, status: "completed") }
  let(:application) do
    JobApplication.create!(run_id: run.id, job_key: "seniorrails|acme", title: "Senior Rails", company: "ACME", message: "Rascunho")
  end
  let(:trail) { JobSearch::AuditTrail.new }

  def execute = JobSearch::ApplicationExecutor.new(audit_trail: trail).execute(application.id)

  it "runs apply_job through the authorizer only after approval, and audits each decision" do
    application.approve!(message: "Mensagem aprovada", by: "joao")

    result = execute

    expect(result).to have_attributes(status: "applied", external_id: start_with("local-"))
    events = trail.events(run.id).map { |event| [ event.event, event.outcome ] }
    expect(events).to include([ "tool.authorization", "allowed" ], [ "application.applied", "completed" ])
    expect(trail.verify(run.id)).to be_valid
  end

  it "blocks the action when the message was changed after the approval" do
    application.approve!(message: "Mensagem aprovada", by: "joao")
    application.update_columns(message: "Mensagem trocada por fora")

    result = execute

    expect(result).to have_attributes(status: "failed", error_class: "JobSearch::ApprovalRequiredError", applied_at: nil)
    expect(trail.events(run.id).map { |event| [ event.event, event.outcome ] }).to include([ "tool.authorization", "denied" ])
  end

  it "does nothing for a proposal that was not approved" do
    expect(execute).to have_attributes(status: "proposed")
    expect(trail.events(run.id)).to be_empty
  end

  it "is idempotent at the destination (a repeated call does not apply twice)" do
    application.approve!(message: "Mensagem aprovada", by: "joao")
    client = JobSearch::LocalApplicationsClient.new

    first = client.create_application(job_id: application.job_key, candidate_id: "me", idempotency_key: "k1")
    again = client.create_application(job_id: application.job_key, candidate_id: "me", idempotency_key: "k1")

    expect(again).to eq(first)
    expect(application.reload.status).to eq("applied")
  end
end

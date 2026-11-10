require "rails_helper"

RSpec.describe "Candidaturas (humano no laço)", type: :request do
  include ActiveJob::TestHelper

  let(:auth) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("joao", "s3cret") } }
  let(:run) { AgentRun.create!(mode: "agent", objective: "x", idempotency_key: SecureRandom.uuid, status: "completed") }
  let(:application) do
    JobApplication.create!(run_id: run.id, job_key: "rails|acme", title: "Senior Rails", company: "ACME",
                           score: 92, score_reason: "Rails sênior", message: "Rascunho do agente <b>x</b>")
  end

  around do |example|
    previous = %w[JOB_AGENT_WEB_USER JOB_AGENT_WEB_PASSWORD].to_h { |key| [ key, ENV[key] ] }
    ENV["JOB_AGENT_WEB_USER"] = "joao"
    ENV["JOB_AGENT_WEB_PASSWORD"] = "s3cret"
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  it "lists the proposals waiting for the user, with the editable draft (escaped)" do
    application

    get job_applications_path, headers: auth

    expect(response.body).to include("Esperando você", "Senior Rails", "Aprovar e candidatar", "Rascunho do agente &lt;b&gt;x&lt;/b&gt;")
    get root_path, headers: auth
    expect(response.body).to include('class="nav-item__badge"')
  end

  it "approves the edited message, audits the human decision and schedules the execution" do
    post approve_job_application_path(application), headers: auth, params: { message: "Minha mensagem final" }

    expect(application.reload).to have_attributes(status: "approved", message: "Minha mensagem final", decided_by: "joao")
    expect(JobSearch::ExecuteApplicationJob).to have_been_enqueued.with(application.id)
    expect(JobSearch::AuditTrail.new.events(run.id).map(&:event)).to eq([ "application.approved" ])
  end

  it "rejects, and a decided proposal cannot be decided again" do
    post reject_job_application_path(application), headers: auth
    expect(application.reload.status).to eq("rejected")

    post approve_job_application_path(application), headers: auth, params: { message: "x" }
    expect(flash[:alert]).to include("já foi decidida")
    expect(JobSearch::ExecuteApplicationJob).not_to have_been_enqueued
  end

  it "shows the proposals of a run on the run page" do
    application

    get run_path(run), headers: auth

    expect(response.body).to include("Candidaturas propostas pelo agente", "Senior Rails")
  end

  it "has the harness propose applications after a completed run when enabled" do
    allow(Rails.configuration.x).to receive(:application_proposals).and_return(true)
    harness = JobSearch::Harness.new(
      container_factory: ->(**) { instance_double(JobSearch::Container, agent: instance_double(JobSearch::Agent, run: JobSearch::AgentState.new(objective: "x").tap(&:complete!))) }
    )
    queued = harness.submit(objective: "Vagas Ruby", mode: "agent")

    harness.execute(queued.id)

    expect(JobSearch::ProposeApplicationsJob).to have_been_enqueued.with(queued.id)
  end
end

require "rails_helper"

RSpec.describe "Feedback 👍/👎", type: :request do
  let(:auth) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("joao", "s3cret") } }
  let(:jobs) do
    [
      { "title" => "Senior Rails", "company" => "ACME", "remote" => true, "score" => 90, "url" => "https://example.com/1" },
      { "title" => "Java Dev", "company" => "Beta", "remote" => false, "score" => 95 }
    ]
  end
  let(:run) do
    AgentRun.create!(mode: "agent", objective: "Vagas", idempotency_key: SecureRandom.uuid, status: "completed",
                     result: { "output" => jobs })
  end

  around do |example|
    previous = %w[JOB_AGENT_WEB_USER JOB_AGENT_WEB_PASSWORD].to_h { |key| [ key, ENV[key] ] }
    ENV["JOB_AGENT_WEB_USER"] = "joao"
    ENV["JOB_AGENT_WEB_PASSWORD"] = "s3cret"
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def mark(job, verdict) = post(job_feedbacks_path, headers: auth,
                                params: { run_id: run.id, job_key: JobFeedback.key_for(job), verdict: verdict })

  it "records the verdict with the job data taken from the run, not from the form" do
    mark(jobs.first, "like")

    expect(response).to redirect_to(run_path(run, anchor: "vagas"))
    expect(JobFeedback.sole).to have_attributes(verdict: "like", title: "Senior Rails", company: "ACME",
                                                url: "https://example.com/1", run_id: run.id)
  end

  it "rejects a job that is not in the run and an unknown verdict" do
    post job_feedbacks_path, headers: auth, params: { run_id: run.id, job_key: "forged|job", verdict: "like" }
    expect(response).to have_http_status(:not_found)

    mark(jobs.first, "love")
    expect(response).to have_http_status(:bad_request)
    expect(JobFeedback.count).to eq(0)
  end

  it "shows the pressed button and sends discarded jobs to the end of the list" do
    mark(jobs.second, "dislike")

    get run_path(run), headers: auth

    body = response.body
    expect(body.index("Senior Rails")).to be < body.index("Java Dev") # 95 pontos, mas descartada
    expect(body).to include("is-dismissed", 'aria-pressed="true"')
  end

  it "lists the marks on the profile page and removes one" do
    mark(jobs.first, "like")

    get edit_profile_path, headers: auth
    expect(response.body).to include("Suas preferências", "Senior Rails", "1 gostei · 0 descartadas")

    delete job_feedback_path(JobFeedback.sole), headers: auth
    expect(JobFeedback.count).to eq(0)
  end
end

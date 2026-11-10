require "rails_helper"

RSpec.describe "Runs UI", type: :request do
  include ActiveJob::TestHelper

  let(:credentials) { { "JOB_AGENT_WEB_USER" => "joao", "JOB_AGENT_WEB_PASSWORD" => "s3cret" } }
  let(:auth) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("joao", "s3cret") } }

  around do |example|
    previous = credentials.keys.to_h { |key| [ key, ENV[key] ] }
    credentials.each { |key, value| ENV[key] = value }
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def create_run(**attributes)
    AgentRun.create!({ mode: "agent", objective: "Vagas Ruby remotas", idempotency_key: SecureRandom.uuid }.merge(attributes))
  end

  describe "authentication" do
    it "refuses to work when no credentials are configured (fail closed)" do
      ENV["JOB_AGENT_WEB_PASSWORD"] = ""

      get root_path, headers: auth

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include("JOB_AGENT_WEB_USER")
    end

    it "asks for credentials and rejects wrong ones" do
      get root_path
      expect(response).to have_http_status(:unauthorized)

      wrong = ActionController::HttpAuthentication::Basic.encode_credentials("joao", "nope")
      get root_path, headers: { "HTTP_AUTHORIZATION" => wrong }
      expect(response).to have_http_status(:unauthorized)
    end

    it "keeps the health check open for the load balancer" do
      get rails_health_check_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /" do
    it "shows the dashboard with the indicators and the recent runs" do
      create_run(objective: "Vagas de Elixir", status: "completed",
                 metrics: { "llm_calls" => 2, "duration_ms" => 1500, "total_tokens" => 1200 })

      get root_path, headers: auth

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Painel", "Vagas de Elixir", "Concluído", "1.5 s", "1.200", "100%")
      expect(response.body).to include(new_run_path)
    end

    it "keeps polling only while some run is active" do
      create_run(status: "completed")
      get root_path, headers: auth
      expect(response.body).to include('data-refresh-active-value="false"')

      create_run(status: "running")
      get root_path, headers: auth
      expect(response.body).to include('data-refresh-active-value="true"')
    end

    it "filters the runs by status and ignores unknown filters" do
      create_run(objective: "Vagas de Elixir", status: "completed")
      create_run(objective: "Vagas de Go", status: "failed")

      get runs_path(status: "failed"), headers: auth
      expect(response.body).to include("Vagas de Go")
      expect(response.body).not_to include("Vagas de Elixir")

      get runs_path(status: "drop table"), headers: auth
      expect(response.body).to include("Vagas de Go", "Vagas de Elixir")
    end

    it "invites the first search when there are no runs" do
      get root_path, headers: auth

      expect(response.body).to include("Nenhuma busca ainda")
    end
  end

  describe "GET /runs/new" do
    it "shows the form with a fresh idempotency key" do
      get new_run_path, headers: auth

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nova busca", "Supervisor", 'name="run[idempotency_key]"')
    end
  end

  describe "POST /runs" do
    let(:params) { { run: { objective: "Vagas Ruby remotas", mode: "supervisor", idempotency_key: "form-123" } } }

    it "submits the run to the harness and opens its page" do
      expect { post runs_path, params: params, headers: auth }.to change(AgentRun, :count).by(1)

      run = AgentRun.last
      expect(run).to have_attributes(mode: "supervisor", status: "queued", idempotency_key: "form-123")
      expect(response).to redirect_to(run_path(run))
      expect(JobSearch::AgentRunJob).to have_been_enqueued.with(run.id)
    end

    it "turns a double submit of the same form into the same run" do
      2.times { post runs_path, params: params, headers: auth }

      expect(AgentRun.where(idempotency_key: "form-123").count).to eq(1)
      expect(JobSearch::AgentRunJob).to have_been_enqueued.exactly(:once)
    end

    it "rejects an empty objective, an oversized one and an unknown mode" do
      post runs_path, params: { run: { objective: "  ", mode: "agent" } }, headers: auth
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Descreva o objetivo")

      post runs_path, params: { run: { objective: "x" * 2_001, mode: "agent" } }, headers: auth
      expect(response.body).to include("no máximo 2000 caracteres")

      post runs_path, params: { run: { objective: "Vagas", mode: "root" } }, headers: auth
      expect(response.body).to include("Modo inválido")
      expect(AgentRun.count).to eq(0)
    end
  end

  describe "GET /runs/:id" do
    it "shows status, metrics, jobs ranked by score and the audit chain" do
      run = create_run(
        status: "completed",
        metrics: { "llm_calls" => 1, "total_tokens" => 1234, "cost_usd" => nil, "duration_ms" => 820 },
        result: { "output" => [
          { "title" => "Java Developer", "company" => "B", "remote" => false, "score" => 0 },
          { "title" => "Senior Ruby Developer", "company" => "A", "remote" => true, "score" => 40 }
        ] }
      )
      trail = JobSearch::AuditTrail.new
      trail.record(run_id: run.id, event: "run.started", outcome: "info")
      trail.record(run_id: run.id, event: "run.finished", outcome: "completed")

      get run_path(run), headers: auth

      body = response.body
      expect(body).to include("Concluído", "1.234", "sem preço", "820 ms", "cadeia íntegra", "run.finished")
      expect(body.index("Senior Ruby Developer")).to be < body.index("Java Developer")
      expect(body).to include('data-refresh-active-value="false"')
      expect(body).not_to include("Cancelar")
    end

    it "shows the AI reason and badge for LLM-scored jobs, escaping the reason" do
      run = create_run(status: "completed", result: { "output" => [
        { "title" => "Senior Rails", "score" => 92, "scored_by" => "llm", "rule_score" => 60,
          "score_reason" => "Rails sênior remoto <b>perfeito</b>" },
        { "title" => "Java Dev", "score" => 10, "scored_by" => "rules" }
      ] })

      get run_path(run), headers: auth

      expect(response.body).to include("Rails sênior remoto &lt;b&gt;perfeito&lt;/b&gt;", "Pela régua fixa: 60")
      expect(response.body.scan('class="score__by"').size).to eq(1)
    end

    it "lists the team agents in delegation order" do
      run = create_run(status: "completed", mode: "supervisor", result: { "agents" => [
        { "delegation" => "ruby", "run_id" => "r1" }, { "delegation" => "rails", "run_id" => "r2" },
        { "delegation" => "rank", "run_id" => "r3" }
      ] })

      get run_path(run), headers: auth

      body = response.body
      expect(body.index(">ruby<")).to be < body.index(">rails<")
      expect(body.index(">rails<")).to be < body.index(">rank<")
    end

    it "flags a tampered audit chain" do
      run = create_run(status: "completed")
      trail = JobSearch::AuditTrail.new
      2.times { |i| trail.record(run_id: run.id, event: "e#{i}", outcome: "info") }
      AgentAuditEvent.where(run_id: run.id, seq: 1).update_all(outcome: "denied")

      get run_path(run), headers: auth

      expect(response.body).to include("cadeia violada no evento 1")
    end

    it "offers cancel and keeps refreshing while the run is active" do
      run = create_run(status: "running")

      get run_path(run), headers: auth

      expect(response.body).to include("Cancelar", "Trabalhando", 'data-refresh-active-value="true"')
    end

    it "escapes text that came from users and tools" do
      run = create_run(status: "completed", objective: "<script>alert(1)</script>",
                       result: { "output" => [ { "title" => "<img src=x onerror=alert(1)>", "score" => 1 } ] })

      get run_path(run), headers: auth

      expect(response.body).not_to include("<script>alert(1)</script>", "<img src=x")
      expect(response.body).to include("&lt;script&gt;")
    end
  end

  describe "POST /runs/:id/cancel" do
    it "cancels a queued run" do
      run = create_run

      post cancel_run_path(run), headers: auth

      expect(run.reload.status).to eq("cancelled")
      expect(response).to redirect_to(run_path(run))
      follow_redirect!(headers: auth)
      expect(response.body).to include("Run cancelado.")
    end
  end

  describe "fresh form and redo" do
    it "never lets the browser or Turbo cache the form (each form has a new key)" do
      get new_run_path, headers: auth

      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.body).to include('name="turbo-cache-control" content="no-cache"')
    end

    it "treats an old form reused for a different search as a new run instead of failing" do
      old = create_run(objective: "Vagas de Go", mode: "supervisor", idempotency_key: "old-key")

      post runs_path, params: { run: { objective: "Vagas de Ruby", mode: "agent", idempotency_key: "old-key" } }, headers: auth

      run = AgentRun.order(:created_at).last
      expect(run).not_to eq(old)
      expect(run).to have_attributes(objective: "Vagas de Ruby", mode: "agent")
      expect(response).to redirect_to(run_path(run))
    end

    it "redoes a search as a new run with the same objective and mode" do
      original = create_run(objective: "Vagas de Elixir", mode: "pipeline", status: "completed")

      expect { post redo_run_path(original), headers: auth }.to change(AgentRun, :count).by(1)

      run = AgentRun.order(:created_at).last
      expect(run).to have_attributes(objective: "Vagas de Elixir", mode: "pipeline", status: "queued")
      expect(run.idempotency_key).not_to eq(original.idempotency_key)
      expect(response).to redirect_to(run_path(run))
      expect(JobSearch::AgentRunJob).to have_been_enqueued.with(run.id)
    end
  end

  describe "soft delete" do
    it "moves a finished run to the trash, out of the list and the indicators, and audits it" do
      run = create_run(objective: "Vagas de Cobol", status: "completed", metrics: { "total_tokens" => 999 })

      delete run_path(run), headers: auth

      expect(run.reload).to be_deleted
      expect(response).to redirect_to(runs_path)
      expect(JobSearch::AuditTrail.new.events(run.id).map(&:event)).to eq([ "run.deleted" ])

      get root_path, headers: auth
      expect(response.body).not_to include("Vagas de Cobol")
      expect(AgentRun.dashboard_stats).to include(total: 0, total_tokens: 0)

      get runs_path(status: "deleted"), headers: auth
      expect(response.body).to include("Vagas de Cobol")
    end

    it "restores a deleted run" do
      run = create_run(status: "completed", deleted_at: Time.current)

      get run_path(run), headers: auth
      expect(response.body).to include("está na lixeira", "Restaurar")

      post restore_run_path(run), headers: auth

      expect(run.reload).not_to be_deleted
      expect(JobSearch::AuditTrail.new.events(run.id).map(&:event)).to eq([ "run.restored" ])
      expect(JobSearch::AuditTrail.new.verify(run.id)).to be_valid
    end

    it "does not delete an active run (cancel it first)" do
      run = create_run(status: "running")

      delete run_path(run), headers: auth

      expect(run.reload).not_to be_deleted
      expect(flash[:alert]).to include("Cancele o run")
    end
  end
end

require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_embedder")

RSpec.describe "Histórico de vagas e parecidas", type: :request do
  include ActiveJob::TestHelper

  let(:auth) { { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("joao", "s3cret") } }
  let(:index) { JobSearch::JobIndex.new(embedder: JobSearch::FakeEmbedder.new) }

  around do |example|
    previous = %w[JOB_AGENT_WEB_USER JOB_AGENT_WEB_PASSWORD].to_h { |key| [ key, ENV[key] ] }
    ENV["JOB_AGENT_WEB_USER"] = "joao"
    ENV["JOB_AGENT_WEB_PASSWORD"] = "s3cret"
    example.run
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  before do
    allow(JobSearch::JobIndex).to receive(:default).and_return(index)
    allow(Rails.configuration.x).to receive(:rag_enabled).and_return(true)
    index.index([
      { title: "Backend Engineer", company: "ACME", remote: true, tags: %w[Python LLM RAG] },
      { title: "Frontend React Developer", company: "Beta", remote: true, tags: %w[React] },
      { title: "AI Platform Engineer", company: "Gamma", remote: true, tags: %w[LLM RAG Agents] }
    ])
  end

  it "lists the most recently seen jobs without a query" do
    get job_postings_path, headers: auth

    expect(response.body).to include("Histórico de vagas", "3 vagas no histórico", "Backend Engineer", "Frontend React Developer")
  end

  it "searches by meaning, showing the similarity" do
    get job_postings_path(q: "LLM RAG"), headers: auth

    body = response.body
    expect(body.index("AI Platform Engineer")).to be < body.index("Frontend React Developer")
    expect(body).to include("Similaridade", "%")
  end

  it "shows the jobs similar to one job" do
    get similar_job_postings_path(key: JobPosting.find_by(title: "Backend Engineer").job_key), headers: auth

    body = response.body
    expect(body).to include("Vagas parecidas", "Vaga de referência")
    expect(body.index("AI Platform Engineer")).to be < body.index("Frontend React Developer")
  end

  it "falls back to the recent list when embeddings are down" do
    allow(index).to receive(:search).and_raise(JobSearch::EmbeddingError, "down")

    get job_postings_path(q: "LLM"), headers: auth

    expect(response.body).to include("busca semântica está indisponível", "Backend Engineer")
  end

  it "schedules the embedding of a new 👍/👎 mark" do
    run = AgentRun.create!(mode: "agent", objective: "x", idempotency_key: SecureRandom.uuid, status: "completed",
                           result: { "output" => [ { "title" => "Go Dev", "company" => "X" } ] })

    post job_feedbacks_path, headers: auth, params: { run_id: run.id, job_key: JobFeedback.key_for({ "title" => "Go Dev", "company" => "X" }), verdict: "like" }

    expect(JobSearch::EmbedFeedbackJob).to have_been_enqueued.with(JobFeedback.sole.id)
  end

  it "links each indexed job of a run to its similar jobs" do
    run = AgentRun.create!(mode: "agent", objective: "x", idempotency_key: SecureRandom.uuid, status: "completed",
                           result: { "output" => [ { "title" => "Backend Engineer", "company" => "ACME" },
                                                   { "title" => "Never Indexed", "company" => "Z" } ] })

    get run_path(run), headers: auth

    expect(response.body.scan("Parecidas").size).to eq(1)
  end
end

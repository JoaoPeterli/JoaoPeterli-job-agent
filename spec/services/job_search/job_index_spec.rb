require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_embedder")

RSpec.describe JobSearch::JobIndex do
  let(:embedder) { JobSearch::FakeEmbedder.new }
  let(:index) { described_class.new(embedder: embedder) }

  def job(title, company: "ACME", tags: [], remote: true)
    { title: title, company: company, location: "Remote", remote: remote, tags: tags, url: "https://example.com/#{title.parameterize}" }
  end

  it "stores the jobs with embeddings and only embeds what is new" do
    index.index([ job("Senior Rails Engineer", tags: %w[Ruby]), job("Java Developer") ])
    index.index([ job("Senior Rails Engineer", tags: %w[Ruby]), job("Python Data Engineer") ])

    expect(JobPosting.count).to eq(3)
    expect(JobPosting.embedded.count).to eq(3)
    expect(embedder.calls.map(&:size)).to eq([ 2, 1 ]) # a vaga repetida não gerou embedding de novo
    expect(JobPosting.find_by(title: "Senior Rails Engineer")).to have_attributes(tags: %w[Ruby], remote: true)
  end

  it "finds similar jobs by meaning, nearest first, excluding the job itself" do
    index.index([ job("Senior Ruby on Rails Engineer", tags: %w[Ruby Rails]), job("Ruby on Rails Developer", tags: %w[Ruby Rails]),
                  job("Java Spring Developer", tags: %w[Java]), job("Marketing Manager", company: "Other") ])
    reference = JobPosting.find_by(title: "Senior Ruby on Rails Engineer")

    similar = index.similar(reference, limit: 3)

    expect(similar.first.title).to eq("Ruby on Rails Developer")
    expect(similar.map(&:title)).not_to include("Senior Ruby on Rails Engineer")
    expect(similar.map(&:neighbor_distance)).to eq(similar.map(&:neighbor_distance).sort)
  end

  it "searches the history semantically from a free-text query" do
    index.index([ job("Backend Engineer", tags: %w[Python LLM RAG]), job("Frontend React Developer", tags: %w[React]) ])

    expect(index.search("LLM RAG engineer", limit: 1).map(&:title)).to eq([ "Backend Engineer" ])
  end

  it "boosts candidates that contain the query terms (hybrid search)" do
    # Vetores controlados: pelo significado a vaga Java fica um pouco mais
    # perto da busca (como acontece com textos no mesmo idioma); os termos
    # LLM e RAG estão só na outra vaga.
    pad = ->(x, y) { [ x, y ] + Array.new(JobSearch::EmbeddingClient::DIMENSIONS - 2, 0.0) }
    controlled = Object.new
    controlled.define_singleton_method(:embed) do |texts|
      texts.map do |text|
        if text.include?("Java") then pad.(0.95, 0.31)
        elsif text.include?("LLM") then pad.(0.90, 0.44)
        else pad.(1.0, 0.0)
        end
      end
    end
    hybrid = described_class.new(embedder: controlled)
    hybrid.index([ job("Desenvolvedor Java Pleno", tags: %w[Java]), job("LLM Engineer", tags: %w[RAG]) ])

    results = hybrid.search("backend com LLM e RAG", limit: 2)

    expect(results.map(&:title)).to eq([ "LLM Engineer", "Desenvolvedor Java Pleno" ])
    expect(results.first.neighbor_distance).to be < results.second.neighbor_distance
  end

  it "reuses the job vector for a feedback (no extra embedding call)" do
    index.index([ job("Senior Rails Engineer") ])
    feedback = JobFeedback.toggle!(job("Senior Rails Engineer").stringify_keys, verdict: "like")
    calls = embedder.calls.size

    index.embed_feedback(feedback)

    expect(feedback.reload.embedding).to eq(JobPosting.sole.embedding)
    expect(embedder.calls.size).to eq(calls)
  end

  it "embeds a feedback whose job was never indexed" do
    feedback = JobFeedback.toggle!({ "title" => "Go Developer", "company" => "X" }, verdict: "dislike")

    index.embed_feedback(feedback)

    expect(feedback.reload.embedding).to be_present
  end
end

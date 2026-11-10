require "rails_helper"
require Rails.root.join("spec/support/job_search/fake_embedder")

RSpec.describe JobSearch::PreferenceMemory do
  let(:index) { JobSearch::JobIndex.new(embedder: JobSearch::FakeEmbedder.new) }
  let(:memory) { described_class.new(index: index) }

  def mark(title, verdict, tags: [])
    job = { "title" => title, "company" => "ACME", "remote" => true, "tags" => tags }
    index.embed_feedback(JobFeedback.toggle!(job, verdict: verdict))
  end

  it "uses the recent memory while no feedback has an embedding" do
    JobFeedback.toggle!({ "title" => "Rails Dev", "company" => "X" }, verdict: "like")

    expect(memory.relevant_for([ { title: "Anything" } ])).to eq(JobFeedback.preferences)
  end

  it "retrieves the marks most similar to the jobs being evaluated, not the most recent ones" do
    mark("Senior Ruby on Rails Engineer", "like", tags: %w[Ruby Rails])
    mark("Java Spring Developer", "dislike", tags: %w[Java Spring])
    12.times { |i| mark("Marketing Specialist #{i}", "like", tags: %w[Marketing]) } # mais recentes, mas irrelevantes

    result = memory.relevant_for([ { title: "Ruby on Rails Developer", company: "Beta", remote: true, tags: %w[Ruby Rails] } ])

    expect(result[:liked].map { |job| job[:title] }).to eq([ "Senior Ruby on Rails Engineer" ])
    expect(result[:disliked]).to eq([]) # Java está longe demais (acima de MAX_DISTANCE)
  end

  it "joins the neighbors of several jobs without duplicates" do
    mark("Senior Ruby on Rails Engineer", "like", tags: %w[Ruby Rails])
    mark("Java Spring Developer", "dislike", tags: %w[Java Spring])

    result = memory.relevant_for([
      { title: "Ruby on Rails Developer", company: "B", remote: true, tags: %w[Ruby Rails] },
      { title: "Senior Ruby Engineer", company: "C", remote: true, tags: %w[Ruby Rails] },
      { title: "Java Spring Engineer", company: "D", remote: true, tags: %w[Java Spring] }
    ])

    expect(result[:liked].map { |job| job[:title] }).to eq([ "Senior Ruby on Rails Engineer" ])
    expect(result[:disliked].map { |job| job[:title] }).to eq([ "Java Spring Developer" ])
  end
end

require "rails_helper"

RSpec.describe JobFeedback do
  let(:job) do
    { "title" => "Senior Rails Engineer", "company" => "ACME", "location" => "Remote", "source" => "Remote OK",
      "url" => "https://remoteok.com/1", "remote" => true, "tags" => %w[Ruby Rails] }
  end

  it "marks, switches and undoes (same verdict again) a job" do
    expect(described_class.toggle!(job, verdict: "like")).to have_attributes(verdict: "like", title: "Senior Rails Engineer",
                                                                             remote: true, tags: %w[Ruby Rails])
    expect(described_class.toggle!(job, verdict: "dislike").verdict).to eq("dislike")
    expect(described_class.count).to eq(1)

    expect(described_class.toggle!(job, verdict: "dislike")).to be_nil
    expect(described_class.count).to eq(0)
  end

  it "identifies the job by the aggregator dedup key (same job in another source)" do
    described_class.toggle!(job, verdict: "like")
    copy = job.merge("title" => "senior rails engineer", "company" => "Acme", "source" => "Himalayas")

    expect(described_class.key_for(copy)).to eq(described_class.key_for(job))
  end

  it "never stores a non-http link" do
    expect(described_class.toggle!(job.merge("url" => "javascript:alert(1)"), verdict: "like").url).to be_nil
  end

  it "builds the memory with the most recent marks of each kind, up to the limit" do
    12.times { |i| described_class.toggle!(job.merge("title" => "Liked #{i}"), verdict: "like") }
    described_class.toggle!(job.merge("title" => "Java Onsite", "remote" => false, "tags" => [ "Java" ]), verdict: "dislike")

    preferences = described_class.preferences

    expect(preferences[:liked].size).to eq(described_class::MAX_IN_MEMORY)
    expect(preferences[:liked].first[:title]).to eq("Liked 11")
    expect(preferences[:disliked]).to eq([ { title: "Java Onsite", company: "ACME", location: "Remote", remote: false, tags: [ "Java" ] } ])
  end
end

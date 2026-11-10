require "rails_helper"

RSpec.describe JobSearch::JobListing do
  def build(**attributes)
    described_class.build(title: "Dev Ruby", url: "https://example.com/job", source: "Teste", **attributes)
  end

  it "accepts only http(s) links, so external data never becomes a javascript: href" do
    expect(build.url).to eq("https://example.com/job")
    expect(build(url: "javascript:alert(1)").url).to be_nil
    expect(build(url: "data:text/html,x").url).to be_nil
    expect(build(url: "not a url").url).to be_nil
  end

  it "normalizes whitespace, blank values and tags" do
    job = build(title: "  Dev \n Ruby ", company: "", tags: [ "Ruby", " Ruby ", nil, "" ], remote: "true")

    expect(job).to have_attributes(title: "Dev Ruby", company: nil, tags: [ "Ruby" ], remote: false)
  end

  it "builds the same dedup key for the same job in different sources" do
    expect(build(title: "Senior Ruby Dev", company: "ACME Inc.").dedup_key)
      .to eq(build(title: "senior ruby dev", company: "Acme Inc").dedup_key)
  end
end

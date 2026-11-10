require "rails_helper"

RSpec.describe "JobSearch errors" do
  it "defines a transient error" do
    expect(JobSearch::TransientError < StandardError).to be(true)
  end

  it "defines a permanent error" do
    expect(JobSearch::PermanentError < StandardError).to be(true)
  end
end

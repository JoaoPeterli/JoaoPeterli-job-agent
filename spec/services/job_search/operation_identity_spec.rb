require "rails_helper"

RSpec.describe "Operation identity" do
  it "identifies equivalent tool executions" do
    first = JobSearch::OperationFingerprint.call(
      tool: "search_jobs",
      arguments: {
        technology: "Ruby",
        remote: true
      }
    )

    second = JobSearch::OperationFingerprint.call(
      tool: "search_jobs",
      arguments: {
        remote: true,
        technology: "Ruby"
      }
    )

    expect(first).to eq(second)
  end

  it "distinguishes different tools" do
    search = JobSearch::OperationFingerprint.call(
      tool: "search_jobs",
      arguments: { technology: "Ruby" }
    )

    analysis = JobSearch::OperationFingerprint.call(
      tool: "analyze_jobs",
      arguments: { technology: "Ruby" }
    )

    expect(search).not_to eq(analysis)
  end
end

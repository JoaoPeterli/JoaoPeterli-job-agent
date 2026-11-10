require "rails_helper"
require Rails.root.join("spec/support/job_search/scripted_llm_client")
require Rails.root.join("spec/support/job_search/captured_events")

RSpec.describe "Agent tracing" do
  def fixture(name)
    File.read(Rails.root.join("spec/fixtures/llm/plans", name))
  end

  let(:events) { JobSearch::CapturedEvents.new }
  let(:objective) { "Encontrar vagas Ruby remotas" }

  def run_agent(responses)
    llm_client = JobSearch::ScriptedLlmClient.new(responses)
    JobSearch::Container.new(llm_client: llm_client, event_logger: events.event_logger)
      .agent(objective: objective)
  end

  def tree(spans)
    by_parent = spans.group_by { |span| span["parent_span_id"] }
    build = lambda do |span|
      [ span["name"], *Array(by_parent[span["span_id"]]).map { |child| build.call(child) } ]
    end

    by_parent[nil].map { |root| build.call(root) }
  end

  it "records the whole run as one trace" do
    state = run_agent([ fixture("unknown_tool.json"), fixture("valid_full_plan.json") ]).run

    spans = events.spans
    expect(spans.map { |span| span["trace_id"] }.uniq).to eq([ state.run_id ])
    expect(tree(spans)).to eq([
      [ "agent.run",
        [ "planning.attempt", [ "llm.plan" ] ],
        [ "planning.attempt", [ "llm.plan" ] ],
        [ "plan.execute", [ "step" ], [ "step" ], [ "step" ] ] ]
    ])
  end

  it "records attributes useful for debugging" do
    run_agent([ fixture("unknown_tool.json"), fixture("valid_full_plan.json") ]).run

    attempts = events.spans.select { |span| span["name"] == "planning.attempt" }
    expect(attempts.first).to include(
      "attempt" => 1, "status" => "error", "error_class" => "JobSearch::PlanningError",
      "retryable" => true, "rejection_reason" => "Unknown tool: linkedin_search"
    )
    expect(attempts.last).to include("attempt" => 2, "status" => "ok", "history" => 0)

    llm = events.spans.find { |span| span["name"] == "llm.plan" }
    expect(llm["prompt_tokens_estimate"]).to be > 0
    expect(llm["response_chars"]).to be > 0

    steps = events.spans.select { |span| span["name"] == "step" }
    expect(steps.map { |span| [ span["step"], span["tool"], span["attempts"] ] }).to eq([
      [ "search", "search_jobs", 1 ], [ "profile", "candidate_profile", 1 ], [ "analyze", "analyze_jobs", 1 ]
    ])

    root = events.spans.find { |span| span["name"] == "agent.run" }
    expect(root).to include("run_status" => "completed", "lessons" => 0, "objective_chars" => objective.length)
  end

  it "marks the failing branch when execution is blocked" do
    allow(JobSearch::SearchJobsTool).to receive(:new).and_raise(JobSearch::PermanentError, "boom")

    expect { run_agent([ fixture("valid_search_only.json") ]).run }.to raise_error(JobSearch::PermanentError)

    statuses = events.spans.to_h { |span| [ span["name"], span["status"] ] }
    expect(statuses).to include("step" => "error", "plan.execute" => "error", "agent.run" => "error")
    expect(events.spans.find { |span| span["name"] == "agent.run" }["run_status"]).to eq("failed")
  end

  it "never logs the objective, the prompt or tool data" do
    run_agent([ fixture("valid_full_plan.json") ]).run

    expect(events.raw).not_to include(objective)
    expect(events.raw).not_to include("Available tools")
    expect(events.raw).not_to include("Example Company")
  end
end

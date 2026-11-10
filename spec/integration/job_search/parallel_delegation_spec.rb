require "rails_helper"
require Rails.root.join("spec/support/job_search/routing_llm_client")
require Rails.root.join("spec/support/job_search/captured_events")

RSpec.describe "Parallel delegation" do
  let(:events) { JobSearch::CapturedEvents.new }
  let(:objective) { "Encontrar vagas remotas de Ruby e de Rails e dizer quais combinam comigo" }
  let(:delay) { 0.3 }

  let(:team_plan) do
    JSON.generate(delegations: [
      { id: "ruby", agent: "researcher", task: "Search remote Ruby jobs", inputs: [] },
      { id: "rails", agent: "researcher", task: "Search remote Rails jobs", inputs: [] },
      { id: "rank", agent: "analyst", task: "Score the jobs for the candidate", inputs: %w[ruby rails] }
    ])
  end

  def search_plan(technology)
    JSON.generate(steps: [
      { name: "search", tool: "search_jobs", arguments: { technology: technology, remote: true }, dependencies: [] }
    ])
  end

  let(:analyst_plan) do
    JSON.generate(steps: [
      { name: "profile", tool: "candidate_profile", arguments: {}, dependencies: [] },
      { name: "analyze", tool: "analyze_jobs",
        arguments: { jobs: { "$ref": "jobs" }, profile: { "$ref": "profile" } }, dependencies: [ "profile" ] }
    ])
  end

  let(:routes) do
    {
      "coordinator of a job search team" => [ team_plan ],
      "Search remote Ruby jobs" => [ search_plan("Ruby") ],
      "Search remote Rails jobs" => [ search_plan("Rails") ],
      "Score the jobs for the candidate" => [ analyst_plan ]
    }
  end

  # Busca lenta e com duração por tecnologia, para provar o paralelismo e
  # inverter a ordem de término (Ruby termina depois de Rails).
  def slow_search(delays = { "Ruby" => delay, "Rails" => delay / 3 }, fail_on: nil)
    allow_any_instance_of(JobSearch::SearchJobsTool).to receive(:call).and_wrap_original do |original, **arguments|
      sleep delays.fetch(arguments[:technology], 0)
      raise JobSearch::PermanentError, "search provider down" if arguments[:technology] == fail_on

      original.call(**arguments)
    end
  end

  def supervisor
    container = JobSearch::Container.new(llm_client: llm_client, event_logger: events.event_logger)
    [ container.supervisor, container.audit_trail ]
  end

  let(:llm_client) { JobSearch::RoutingLlmClient.new(routes) }

  def span(name, **attributes)
    events.spans.select { |s| s["name"] == name }.find { |s| attributes.all? { |k, v| s[k.to_s] == v } }
  end

  it "runs independent researchers at the same time" do
    slow_search({ "Ruby" => delay, "Rails" => delay })
    team, = supervisor

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = team.run(objective: objective)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(result.status).to eq(:completed)
    expect(elapsed).to be < (2 * delay)

    wave = span("delegation.wave", wave: 0)
    expect(wave).to include("size" => 2, "parallel" => 2)
    researchers = events.spans.select { |s| s["name"] == "delegation" && s["agent"] == "researcher" }
    expect(wave["duration_ms"]).to be < researchers.sum { |s| s["duration_ms"] }
  end

  it "keeps results, messages and the analyst's input in plan order, whatever finishes first" do
    slow_search
    team, = supervisor

    result = team.run(objective: objective)

    expect(result.output.value.map { |job| job[:title] }).to eq([ "Senior Ruby Developer", "Senior Rails Developer" ])
    expect(result.messages.map { |m| [ m.kind, m.payload[:delegation] ] }).to eq([
      [ :task, "ruby" ], [ :task, "rails" ], [ :result, "ruby" ], [ :result, "rails" ],
      [ :task, "rank" ], [ :result, "rank" ]
    ])
  end

  it "parents every agent span to its wave and keeps one trace" do
    slow_search
    team, = supervisor

    result = team.run(objective: objective)

    expect(events.spans.map { |s| s["trace_id"] }.uniq).to eq([ result.run_id ])
    wave = span("delegation.wave", wave: 0)
    ruby = span("delegation", delegation: "ruby")
    rails = span("delegation", delegation: "rails")
    expect([ ruby, rails ].map { |s| s["parent_span_id"] }).to all(eq(wave["span_id"]))

    agent_runs = events.spans.select { |s| s["name"] == "agent.run" }
    expect(agent_runs.map { |s| s["parent_span_id"] }).to match_array(
      events.spans.select { |s| s["name"] == "delegation" }.map { |s| s["span_id"] }
    )
    metrics = events.all.select { |e| e["event"] == "run.metrics" }
    expect(metrics.size).to eq(1)
    expect(metrics.first).to include("llm_calls" => 4, "tool_calls" => 4)
  end

  it "keeps a valid audit chain while agents run in parallel" do
    slow_search
    team, audit_trail = supervisor

    result = team.run(objective: objective)

    expect(audit_trail.verify(result.run_id)).to be_valid
    result.agent_run_ids.each_value { |run_id| expect(audit_trail.verify(run_id)).to be_valid }
  end

  it "fails fast: lets the running sibling finish, but starts no new wave" do
    slow_search({ "Ruby" => 0, "Rails" => delay }, fail_on: "Ruby")
    team, = supervisor

    expect { team.run(objective: objective) }.to raise_error(JobSearch::PipelineStageError) { |error|
      expect(error.stage).to eq("ruby")
      expect(error.cause).to be_a(JobSearch::PermanentError)
      expect(error.messages.map { |m| [ m.kind, m.payload[:delegation] ] }).to eq([
        [ :task, "ruby" ], [ :task, "rails" ], [ :failure, "ruby" ], [ :result, "rails" ]
      ])
    }

    expect(llm_client.prompts.grep(/Score the jobs/)).to be_empty
    expect(span("delegation", delegation: "rails")).to include("status" => "ok")
  end

  it "runs one delegation at a time when max_parallel is 1" do
    stub_const("JobSearch::Container::MAX_PARALLEL_DELEGATIONS", 1)
    slow_search({ "Ruby" => delay, "Rails" => delay })
    team, = supervisor

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    team.run(objective: objective)

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= (2 * delay)
    expect(span("delegation.wave", wave: 0)).to include("parallel" => 1)
  end
end

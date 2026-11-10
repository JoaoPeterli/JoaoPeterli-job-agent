require "rails_helper"

RSpec.describe JobSearch::AgentInput do
  it "summarizes name, description and size without the value" do
    input = described_class.new(name: "jobs", description: "jobs found", value: [ { title: "Secret title" } ])

    expect(input.name).to eq(:jobs)
    expect(input.summary).to eq("jobs: jobs found (1 items)")
    expect(input.summary).not_to include("Secret title")
  end

  it "omits the size for scalar values" do
    expect(described_class.new(name: :note, description: "a note", value: "text").summary).to eq("note: a note")
  end
end

RSpec.describe JobSearch::AgentMessage do
  it "builds a message with an id and frozen payload" do
    message = described_class.new(kind: "task", from: :coordinator, to: :researcher, pipeline_run_id: "p1",
                                  payload: { inputs: [] })

    expect(message).to have_attributes(kind: :task, from: "coordinator", to: "researcher")
    expect(message.id).to be_present
    expect(message.payload).to be_frozen
    expect(message.to_h).to include(kind: "task", pipeline_run_id: "p1")
  end

  it "rejects unknown kinds" do
    expect { described_class.new(kind: :gossip, from: "a", to: "b", pipeline_run_id: "p") }
      .to raise_error(ArgumentError, "Unknown message kind: gossip")
  end
end

RSpec.describe JobSearch::AgentProfile do
  def state_with(observations)
    state = JobSearch::AgentState.new(objective: "x")
    observations.each do |name, tool, value|
      state.start_step!(name, tool: tool)
      state.add_observation(name, value)
      state.complete_step!(name)
    end
    state
  end

  it "concatenates list outputs of every step that used the output tool" do
    state = state_with([
      [ :ruby, :search_jobs, [ { title: "A" } ] ],
      [ :profile, :candidate_profile, { skills: [] } ],
      [ :rails, :search_jobs, [ { title: "B" } ] ]
    ])

    expect(JobSearch::AgentProfiles::RESEARCHER.output_from(state)).to eq([ { title: "A" }, { title: "B" } ])
  end

  it "ignores steps that did not complete" do
    state = state_with([ [ :ruby, :search_jobs, [ { title: "A" } ] ] ])
    state.start_step!(:broken, tool: :search_jobs)
    state.fail_step!(:broken)

    expect(JobSearch::AgentProfiles::RESEARCHER.output_from(state)).to eq([ { title: "A" } ])
  end

  it "wraps the output as an input for the next agent" do
    state = state_with([ [ :ruby, :search_jobs, [ { title: "A" } ] ] ])

    input = JobSearch::AgentProfiles::RESEARCHER.output_input(state)

    expect(input).to have_attributes(name: :jobs, value: [ { title: "A" } ])
  end

  it "has disjoint tools for the specialists" do
    researcher = JobSearch::AgentProfiles::RESEARCHER.allowed_tools
    analyst = JobSearch::AgentProfiles::ANALYST.allowed_tools

    expect(researcher & analyst).to be_empty
    expect(JobSearch::AgentProfiles.fetch("analyst")).to eq(JobSearch::AgentProfiles::ANALYST)
    expect { JobSearch::AgentProfiles.fetch("hacker") }.to raise_error(KeyError)
  end
end

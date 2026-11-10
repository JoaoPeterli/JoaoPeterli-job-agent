require "rails_helper"

RSpec.describe JobSearch::Plan do
  describe "#initialize" do
    it "stores its steps" do
      action = JobSearch::AgentAction.new(
        tool: :search_jobs
      )

      step = JobSearch::Step.new(
        name: :search,
        action: action
      )

      plan = described_class.new(
        steps: [ step ]
      )

      expect(plan.steps).to eq([ step ])
    end
  end

  describe "#ready_steps" do
  let(:action) do
    JobSearch::AgentAction.new(
      tool: :search_jobs
    )
  end

  let(:search) do
    JobSearch::Step.new(
      name: :search,
      action: action
    )
  end

  let(:profile) do
    JobSearch::Step.new(
      name: :profile,
      action: action
    )
  end

  let(:details) do
    JobSearch::Step.new(
      name: :details,
      action: action,
      dependencies: [ :search ]
    )
  end

  let(:compare) do
    JobSearch::Step.new(
      name: :compare,
      action: action,
      dependencies: [ :details, :profile ]
    )
  end

  let(:rank) do
    JobSearch::Step.new(
      name: :rank,
      action: action,
      dependencies: [ :compare ]
    )
  end

  let(:plan) do
    described_class.new(
      steps: [
        search,
        profile,
        details,
        compare,
        rank
      ]
    )
  end

  it "returns steps without dependencies initially" do
    ready = plan.ready_steps(
      completed_steps: []
    )

    expect(ready.map(&:name))
      .to eq([ :search, :profile ])
  end

  it "returns newly available steps" do
    ready = plan.ready_steps(
      completed_steps: [ :search ]
    )

    expect(ready.map(&:name))
      .to eq([ :profile, :details ])
  end

  it "returns compare when its dependencies are completed" do
    ready = plan.ready_steps(
      completed_steps: [
        :search,
        :profile,
        :details
      ]
    )

    expect(ready.map(&:name))
      .to eq([ :compare ])
  end

  it "returns rank after compare is completed" do
    ready = plan.ready_steps(
      completed_steps: [
        :search,
        :profile,
        :details,
        :compare
      ]
    )

    expect(ready.map(&:name))
      .to eq([ :rank ])
  end
end

 describe "validation" do
  let(:action) do
    JobSearch::AgentAction.new(
      tool: :search_jobs
    )
  end

  it "rejects duplicated step names" do
    first = JobSearch::Step.new(
      name: :search,
      action: action
    )

    second = JobSearch::Step.new(
      name: :search,
      action: action
    )

    expect {
      described_class.new(
        steps: [ first, second ]
      )
    }.to raise_error(
      ArgumentError,
      "Duplicated step: search"
    )
  end

  it "rejects unknown dependencies" do
  step = JobSearch::Step.new(
    name: :details,
    action: action,
    dependencies: [ :search ]
  )

  expect {
    described_class.new(
      steps: [ step ]
    )
  }.to raise_error(
    ArgumentError,
    "Unknown dependency: search"
  )
end

 it "rejects cyclic dependencies" do
  step_a = JobSearch::Step.new(
    name: :a,
    action: action,
    dependencies: [ :b ]
  )

  step_b = JobSearch::Step.new(
    name: :b,
    action: action,
    dependencies: [ :a ]
  )

  expect {
    described_class.new(
      steps: [ step_a, step_b ]
    )
  }.to raise_error(
    ArgumentError,
    "Cycle detected"
  )
end

it "rejects references to unknown steps" do
  search_action = JobSearch::AgentAction.new(
    tool: :search_jobs
  )

  analyze_action = JobSearch::AgentAction.new(
    tool: :analyze_jobs,
    arguments: {
      jobs: JobSearch::ObservationReference.new(
        step_name: :unknown
      )
    }
  )

  search_step = JobSearch::Step.new(
    name: :search,
    action: search_action
  )

  analyze_step = JobSearch::Step.new(
    name: :analyze,
    action: analyze_action,
    dependencies: [
      :search
    ]
  )

  expect {
    described_class.new(
      steps: [
        search_step,
        analyze_step
      ]
    )
  }.to raise_error(
    ArgumentError,
    "Unknown observation reference: unknown"
  )
end

it "rejects observation references without dependency" do
  search_action = JobSearch::AgentAction.new(
    tool: :search_jobs
  )

  analyze_action = JobSearch::AgentAction.new(
    tool: :analyze_jobs,
    arguments: {
      jobs: JobSearch::ObservationReference.new(
        step_name: :search
      )
    }
  )

  search_step = JobSearch::Step.new(
    name: :search,
    action: search_action
  )

  analyze_step = JobSearch::Step.new(
    name: :analyze,
    action: analyze_action
  )

  expect {
    described_class.new(
      steps: [
        search_step,
        analyze_step
      ]
    )
  }.to raise_error(
    ArgumentError,
    "Missing dependency for observation reference: analyze -> search"
  )
end
end
end

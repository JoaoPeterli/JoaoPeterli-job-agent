require "rails_helper"

RSpec.describe JobSearch::Step do
  describe "#initialize" do
    it "stores name, action and dependencies" do
      action = JobSearch::AgentAction.new(
        tool: :search_jobs
      )

      step = described_class.new(
        name: :details,
        action: action,
        dependencies: [ :search ]
      )

      expect(step.name).to eq(:details)
      expect(step.action).to eq(action)
      expect(step.dependencies).to eq([ :search ])
    end

    it "defaults dependencies to an empty array" do
      action = JobSearch::AgentAction.new(
        tool: :search_jobs
      )

      step = described_class.new(
        name: :search,
        action: action
      )

      expect(step.dependencies).to eq([])
    end
  end

  describe "#ready?" do
  it "returns true when the step has no dependencies" do
    action = JobSearch::AgentAction.new(
      tool: :search_jobs
    )

    step = described_class.new(
      name: :search,
      action: action
    )

    expect(step.ready?([])).to be(true)
  end

  it "returns false when dependencies are not completed" do
    action = JobSearch::AgentAction.new(
      tool: :search_jobs
    )

    step = described_class.new(
      name: :details,
      action: action,
      dependencies: [ :search ]
    )

    expect(step.ready?([])).to be(false)
  end

  it "returns true when all dependencies are completed" do
    action = JobSearch::AgentAction.new(
      tool: :search_jobs
    )

    step = described_class.new(
      name: :compare,
      action: action,
      dependencies: [ :details, :profile ]
    )

    completed_steps = [
      :details,
      :profile
    ]

    expect(
      step.ready?(completed_steps)
    ).to be(true)
  end
end
end

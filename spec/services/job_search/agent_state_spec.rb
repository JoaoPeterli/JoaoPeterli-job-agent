require "rails_helper"

RSpec.describe JobSearch::AgentState do
  describe "#initialize" do
    it "starts with running status" do
      state = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      expect(state.objective)
        .to eq("Encontrar vagas Ruby")

      expect(state.status)
        .to eq(:running)
    end

    it "starts with empty actions" do
      state = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      expect(state.actions)
        .to eq([])
    end

    it "starts with empty observations" do
      state = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      expect(state.observations)
        .to eq({})
    end

    it "starts with empty step statuses" do
      state = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      expect(state.step_statuses)
        .to eq({})
    end

    it "starts with empty step errors" do
      state = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      expect(state.step_errors)
        .to eq({})
    end
  end

  describe "actions" do
    it "stores actions" do
      state = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      action = JobSearch::AgentAction.new(
        tool: :search_jobs
      )

      state.add_action(action)

      expect(state.actions)
        .to eq([ action ])
    end
  end

  describe "observations" do
    it "stores an observation by step name" do
      state = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      observation = [
        {
          title: "Senior Ruby Developer"
        }
      ]

      state.add_observation(
        :search,
        observation
      )

      expect(
        state.observation_for(:search)
      ).to eq(observation)
    end

    it "returns nil for an unknown observation" do
      state = described_class.new(
        objective: "Encontrar vagas Ruby"
      )

      expect(
        state.observation_for(:unknown)
      ).to be_nil
    end
  end

  describe "step status" do
    let(:state) do
      described_class.new(
        objective: "Encontrar vagas Ruby"
      )
    end

    it "returns pending for a step without execution" do
      expect(
        state.step_status(:search)
      ).to eq(:pending)
    end

    it "marks a step as running" do
      state.start_step!(:search)

      expect(
        state.step_status(:search)
      ).to eq(:running)
    end

    it "marks a step as completed" do
      state.start_step!(:search)

      state.complete_step!(:search)

      expect(
        state.step_status(:search)
      ).to eq(:completed)
    end

    it "marks a step as failed" do
      state.start_step!(:search)

      state.fail_step!(:search)

      expect(
        state.step_status(:search)
      ).to eq(:failed)
    end
  end

  describe "step errors" do
    let(:state) do
      described_class.new(
        objective: "Encontrar vagas Ruby"
      )
    end

    it "stores an error for a step" do
      error = StandardError.new(
        "API unavailable"
      )

      state.fail_step!(
        :search,
        error: error
      )

      expect(
        state.step_status(:search)
      ).to eq(:failed)

      expect(
        state.error_for(:search)
      ).to eq(error)
    end

    it "stores the error message" do
      error = StandardError.new(
        "API unavailable"
      )

      state.fail_step!(
        :search,
        error: error
      )

      expect(
        state.error_for(:search).message
      ).to eq("API unavailable")
    end

    it "returns nil when the step has no error" do
      expect(
        state.error_for(:search)
      ).to be_nil
    end
  end

  describe "agent status" do
    let(:state) do
      described_class.new(
        objective: "Encontrar vagas Ruby"
      )
    end

    it "marks the agent as completed" do
      state.complete!

      expect(state.status)
        .to eq(:completed)
    end

    it "marks the agent as failed" do
      state.failed!

      expect(state.status)
        .to eq(:failed)
    end
  end

  describe "step attempts" do
  let(:state) do
    described_class.new(
      objective: "Encontrar vagas Ruby"
    )
  end

  it "returns zero when the step has no attempts" do
    expect(
      state.attempts_for(:search)
    ).to eq(0)
  end

  it "records the latest attempt number" do
    state.record_attempt(:search, 1)
    state.record_attempt(:search, 2)
    state.record_attempt(:search, 3)

    expect(
      state.attempts_for(:search)
    ).to eq(3)
  end
end
end

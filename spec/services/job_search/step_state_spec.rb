require "rails_helper"

RSpec.describe JobSearch::StepState do
  it "starts pending" do
    state = described_class.new

    expect(state.status)
      .to eq(:pending)

    expect(state.attempts)
      .to eq(0)

    expect(state.observation)
      .to be_nil

    expect(state.error)
      .to be_nil
  end

  it "marks the step as running" do
    state = described_class.new

    state.start!

    expect(state.status)
      .to eq(:running)
  end

  it "stores an observation" do
    state = described_class.new

    observation = {
      jobs: [ "Ruby Developer" ]
    }

    state.add_observation(
      observation
    )

    expect(state.observation)
      .to eq(observation)

    expect(state.status)
      .to eq(:pending)
  end

  it "marks the step as completed" do
    state = described_class.new

    state.start!

    state.complete!

    expect(state.status)
      .to eq(:completed)
  end

  it "stores observation and completes the step" do
    state = described_class.new

    observation = {
      jobs: [ "Ruby Developer" ]
    }

    state.start!

    state.add_observation(
      observation
    )

    state.complete!

    expect(state.status)
      .to eq(:completed)

    expect(state.observation)
      .to eq(observation)
  end

  it "marks the step as failed and stores the error" do
    state = described_class.new

    error = StandardError.new(
      "API unavailable"
    )

    state.fail!(
      error: error
    )

    expect(state.status)
      .to eq(:failed)

    expect(state.error)
      .to eq(error)
  end

  it "records the latest attempt" do
    state = described_class.new

    state.record_attempt(1)
    state.record_attempt(2)
    state.record_attempt(3)

    expect(state.attempts)
      .to eq(3)
  end

  describe "execution time" do
  it "records execution duration" do
    clock = instance_double(
      JobSearch::Clock
    )

    allow(clock)
      .to receive(:now)
      .and_return(
        10.0,
        12.5
      )

    state = described_class.new(
      clock: clock
    )

    state.start!
    state.complete!

    expect(state.started_at)
      .to eq(10.0)

    expect(state.finished_at)
      .to eq(12.5)

    expect(state.duration)
      .to eq(2.5)
  end

  it "records duration when execution fails" do
    clock = instance_double(
      JobSearch::Clock
    )

    allow(clock)
      .to receive(:now)
      .and_return(
        20.0,
        23.0
      )

    state = described_class.new(
      clock: clock
    )

    state.start!

    state.fail!(
      error: StandardError.new(
        "API unavailable"
      )
    )

    expect(state.duration)
      .to eq(3.0)

    expect(state.status)
      .to eq(:failed)
  end

  it "returns nil while execution has not finished" do
    clock = instance_double(
      JobSearch::Clock
    )

    allow(clock)
      .to receive(:now)
      .and_return(10.0)

    state = described_class.new(
      clock: clock
    )

    state.start!

    expect(state.duration)
      .to be_nil
  end
end
end

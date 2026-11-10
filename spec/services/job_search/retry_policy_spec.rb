require "rails_helper"

RSpec.describe JobSearch::RetryPolicy do
  describe "#call" do
    let(:backoff_strategy) do
      instance_double(JobSearch::BackoffStrategy)
    end

    let(:sleeper) do
      instance_double(JobSearch::Sleeper)
    end

    let(:policy) do
      described_class.new(
        max_attempts: 3,
        backoff_strategy: backoff_strategy,
        sleeper: sleeper
      )
    end

    before do
      allow(backoff_strategy)
        .to receive(:delay_for)
        .and_return(1)

      allow(sleeper)
        .to receive(:sleep)
    end

    it "retries transient errors" do
      attempts = 0

      result = policy.call do
        attempts += 1

        if attempts < 3
          raise JobSearch::TransientError,
                "API unavailable"
        end

        "success"
      end

      expect(result).to eq("success")
      expect(attempts).to eq(3)
    end

    it "raises after reaching max attempts" do
      attempts = 0

      expect {
        policy.call do
          attempts += 1

          raise JobSearch::TransientError,
                "API unavailable"
        end
      }.to raise_error(
        JobSearch::TransientError,
        "API unavailable"
      )

      expect(attempts).to eq(3)
    end

    it "waits using the backoff strategy before retrying" do
      attempts = 0

      expect(backoff_strategy)
        .to receive(:delay_for)
        .with(1)
        .and_return(2)

      expect(sleeper)
        .to receive(:sleep)
        .with(2)

      policy = described_class.new(
        max_attempts: 2,
        backoff_strategy: backoff_strategy,
        sleeper: sleeper
      )

      result = policy.call do
        attempts += 1

        if attempts == 1
          raise JobSearch::TransientError,
                "API unavailable"
        end

        "success"
      end

      expect(result).to eq("success")
      expect(attempts).to eq(2)
    end
  end

  it "notifies each execution attempt" do
  backoff_strategy = instance_double(
    JobSearch::BackoffStrategy
  )

  sleeper = instance_double(
    JobSearch::Sleeper
  )

  allow(backoff_strategy)
    .to receive(:delay_for)
    .and_return(1)

  allow(sleeper)
    .to receive(:sleep)

  retry_policy = described_class.new(
    max_attempts: 3,
    backoff_strategy: backoff_strategy,
    sleeper: sleeper
  )

  attempts = []

  execution_count = 0

  result = retry_policy.call(
    on_attempt: ->(attempt) {
      attempts << attempt
    }
  ) do
    execution_count += 1

    if execution_count < 3
      raise JobSearch::TransientError,
            "Temporary failure"
    end

    "success"
  end

  expect(result)
    .to eq("success")

  expect(attempts)
    .to eq([ 1, 2, 3 ])
end
end

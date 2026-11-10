require "rails_helper"

RSpec.describe JobSearch::LlmBudget do
  def usage(total)
    JobSearch::LlmUsage.new(input_tokens: total, output_tokens: 0)
  end

  it "allows calls while under the limits" do
    budget = described_class.new(max_total_tokens: 100, max_cost_usd: 1.0)
    budget.record(usage: usage(99), cost_usd: 0.99)

    expect { budget.check! }.not_to raise_error
    expect(budget.calls).to eq(1)
  end

  it "blocks the next call once the token limit is reached" do
    budget = described_class.new(max_total_tokens: 100)
    budget.record(usage: usage(60), cost_usd: nil)
    budget.record(usage: usage(40), cost_usd: nil)

    expect { budget.check! }.to raise_error(JobSearch::LlmBudgetExceeded, /100\/100 tokens/) { |error|
      expect(error).not_to be_retryable
      expect(error).to be_a(JobSearch::PlanningError)
    }
  end

  it "blocks the next call once the cost limit is reached" do
    budget = described_class.new(max_total_tokens: 1_000, max_cost_usd: 0.01)
    budget.record(usage: usage(10), cost_usd: 0.01)

    expect { budget.check! }.to raise_error(JobSearch::LlmBudgetExceeded, /\$0\.0100\/\$0\.0100/)
  end

  it "ignores the cost limit when the cost is unknown" do
    budget = described_class.new(max_total_tokens: 1_000, max_cost_usd: 0.01)
    budget.record(usage: usage(10), cost_usd: nil)

    expect { budget.check! }.not_to raise_error
    expect(budget.cost_usd).to eq(0.0)
  end

  it "rejects invalid limits" do
    expect { described_class.new(max_total_tokens: 0) }.to raise_error(ArgumentError)
    expect { described_class.new(max_total_tokens: 1, max_cost_usd: 0) }.to raise_error(ArgumentError)
  end
end

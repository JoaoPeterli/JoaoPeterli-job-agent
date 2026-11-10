require "rails_helper"

RSpec.describe JobSearch::LlmPricing do
  let(:pricing) do
    described_class.new(input_per_million: 2.0, cached_input_per_million: 0.5, output_per_million: 8.0)
  end

  it "charges input, cached input and output tokens at their own rates" do
    usage = JobSearch::LlmUsage.new(input_tokens: 1_000, cached_input_tokens: 400, output_tokens: 500)

    # 600 * 2.0 + 400 * 0.5 + 500 * 8.0 = 5_400 por milhão
    expect(pricing.cost_usd(usage)).to eq(0.0054)
  end

  it "uses the input rate for cached tokens when no cache rate is given" do
    pricing = described_class.new(input_per_million: 2.0, output_per_million: 8.0)
    usage = JobSearch::LlmUsage.new(input_tokens: 1_000_000, cached_input_tokens: 1_000_000, output_tokens: 0)

    expect(pricing.cost_usd(usage)).to eq(2.0)
  end

  it "rejects non-numeric prices" do
    expect { described_class.new(input_per_million: "abc", output_per_million: 1) }.to raise_error(ArgumentError)
  end
end

RSpec.describe JobSearch::LlmUsage do
  it "derives the total when the provider does not send it" do
    usage = described_class.new(input_tokens: 10, output_tokens: 5)

    expect(usage.total_tokens).to eq(15)
    expect(usage.cached_input_tokens).to eq(0)
  end
end

require "rails_helper"
require "tempfile"

RSpec.describe JobSearch::LlmPricingTable do
  let(:pricing) { JobSearch::LlmPricing.new(input_per_million: 1.0, output_per_million: 4.0) }
  let(:mini_pricing) { JobSearch::LlmPricing.new(input_per_million: 0.1, output_per_million: 0.4) }
  let(:table) { described_class.new("gpt-x" => pricing, "gpt-x-mini" => mini_pricing) }

  describe "#for" do
    it "finds a model by its exact name" do
      expect(table.for("gpt-x")).to eq(pricing)
    end

    it "matches a dated snapshot by the longest registered prefix" do
      expect(table.for("gpt-x-2026-08-01")).to eq(pricing)
      expect(table.for("gpt-x-mini-2026-08-01")).to eq(mini_pricing)
    end

    it "does not match a different model that only shares a prefix" do
      expect(table.for("gpt-xl")).to be_nil
      expect(table.for(nil)).to be_nil
    end
  end

  describe "#cost_usd" do
    it "is unknown without usage or without a price" do
      usage = JobSearch::LlmUsage.new(input_tokens: 10, output_tokens: 10)

      expect(table.cost_usd(model: "gpt-x", usage: nil)).to be_nil
      expect(table.cost_usd(model: "other", usage: usage)).to be_nil
      expect(table.cost_usd(model: "gpt-x", usage: usage)).to eq(0.00005)
    end
  end

  describe ".load" do
    def load_yaml(content)
      Tempfile.create([ "pricing", ".yml" ]) do |file|
        file.write(content)
        file.flush
        described_class.load(file.path)
      end
    end

    it "loads prices per million tokens" do
      table = load_yaml(<<~YAML)
        gpt-x:
          input_per_million: 1.25
          cached_input_per_million: 0.125
          output_per_million: 10
      YAML

      expect(table.for("gpt-x")).to eq(
        JobSearch::LlmPricing.new(input_per_million: 1.25, cached_input_per_million: 0.125, output_per_million: 10)
      )
    end

    it "skips models whose prices are not filled in" do
      table = load_yaml(<<~YAML)
        gpt-x:
          input_per_million:
          output_per_million:
      YAML

      expect(table.for("gpt-x")).to be_nil
    end

    it "returns an empty table for a missing file" do
      expect(described_class.load("/nonexistent/pricing.yml").for("gpt-x")).to be_nil
    end

    it "parses the project's pricing file" do
      expect { described_class.load(Rails.root.join("config/llm_pricing.yml")) }.not_to raise_error
    end
  end
end

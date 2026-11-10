require "rails_helper"

RSpec.describe JobSearch::Observability::NullTracer do
  it "runs the block and returns its value" do
    expect(described_class.new.span("work", size: 1) { |span| span.set(:a, 1) && :ok }).to eq(:ok)
  end

  it "ignores logs" do
    expect(described_class.new.log(:warn, event: "x")).to be_nil
  end
end

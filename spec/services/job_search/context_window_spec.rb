require "rails_helper"

RSpec.describe JobSearch::ContextWindow do
  def section(name, content, **options)
    JobSearch::PromptSection.new(name: name, content: content, **options)
  end

  it "rejects a non-positive budget" do
    expect { described_class.new(max_input_tokens: 0) }
      .to raise_error(ArgumentError)
  end

  it "joins sections in their original order" do
    window = described_class.new(max_input_tokens: 1_000)

    result = window.build([
      section(:a, "first"),
      section(:b, "second", required: false),
      section(:c, "third")
    ])

    expect(result.text).to eq("first\n\nsecond\n\nthird")
    expect(result.dropped_sections).to be_empty
    expect(result.truncated_sections).to be_empty
  end

  it "ignores blank sections" do
    window = described_class.new(max_input_tokens: 1_000)

    result = window.build([ section(:a, "first"), section(:b, "  ") ])

    expect(result.text).to eq("first")
  end

  it "reports the estimated token count" do
    window = described_class.new(max_input_tokens: 1_000)

    result = window.build([ section(:a, "x" * 40) ])

    expect(result.token_count).to eq(10)
  end

  it "fails when required sections do not fit together" do
    window = described_class.new(max_input_tokens: 10)

    expect do
      window.build([ section(:a, "x" * 30), section(:b, "y" * 30) ])
    end.to raise_error(JobSearch::ContextBudgetExceeded, /Required prompt sections/)
  end

  it "fails when a required section exceeds its own limit" do
    window = described_class.new(max_input_tokens: 1_000)

    expect do
      window.build([ section(:objective, "x" * 100, max_tokens: 5) ])
    end.to raise_error(JobSearch::ContextBudgetExceeded, /objective exceeds 5 tokens/)
  end

  it "truncates an optional section that exceeds its own limit" do
    window = described_class.new(max_input_tokens: 1_000)

    result = window.build([ section(:repair, "x" * 1_000, required: false, max_tokens: 20) ])

    expect(result.text).to end_with("...[truncated]")
    expect(result.truncated_sections).to eq([ :repair ])
  end

  it "drops optional sections that do not fit in the remaining budget" do
    window = described_class.new(max_input_tokens: 20)

    result = window.build([
      section(:core, "x" * 40),
      section(:extra, "y" * 200, required: false),
      section(:small, "z", required: false)
    ])

    expect(result.text).to eq("#{'x' * 40}\n\nz")
    expect(result.dropped_sections).to eq([ :extra ])
  end

  it "never produces a prompt above the budget" do
    window = described_class.new(max_input_tokens: 30)

    result = window.build([
      section(:a, "x" * 50),
      section(:b, "y" * 50, required: false),
      section(:c, "z" * 50, required: false)
    ])

    expect(result.token_count).to be <= 30
  end

  it "raises a non-retryable planning error" do
    window = described_class.new(max_input_tokens: 1)

    expect { window.build([ section(:a, "x" * 100) ]) }
      .to raise_error(JobSearch::PlanningError) { |error| expect(error).not_to be_retryable }
  end
end

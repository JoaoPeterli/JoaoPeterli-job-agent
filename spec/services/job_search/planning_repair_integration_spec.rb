
require "rails_helper"

RSpec.describe "Planning repair integration" do
  let(:llm_client) do
    instance_double(JobSearch::LlmClient)
  end

  let(:registry) do
    JobSearch::ToolRegistry.new
  end

  let(:planner) do
    JobSearch::LlmPlanner.new(
      llm_client: llm_client,
      registry: registry
    )
  end

  let(:retry_policy) do
    JobSearch::PlanningRetryPolicy.new(
      max_attempts: 3
    )
  end

  let(:valid_response) do
    JSON.generate(
      steps: [
        {
          name: "search",
          tool: "search_jobs",
          arguments: {},
          dependencies: []
        }
      ]
    )
  end

  before do
    registry.register(
      :search_jobs,
      JobSearch::SearchJobsTool
    )
  end

  def generate_plan
    retry_policy.call(
      objective: "Find Ruby jobs"
    ) do |context|
      planner.plan(context: context)
    end
  end

  it "repairs an invalid plan on the second attempt" do
    allow(llm_client)
      .to receive(:complete)
      .and_return(
        '{"steps": "invalid"}',
        valid_response
      )

    plan = generate_plan

    expect(plan).to be_a(JobSearch::Plan)
    expect(plan.steps.first.name).to eq(:search)

    expect(llm_client)
      .to have_received(:complete).twice
  end

  it "includes the validation error in the repair prompt" do
    prompts = []

    allow(llm_client)
      .to receive(:complete) do |prompt:|
        prompts << prompt

        prompts.length == 1 ?
          '{"steps": "invalid"}' :
          valid_response
      end

    generate_plan

    expect(prompts.length).to eq(2)

    expect(prompts.last).to include(
      "This is planning attempt 2",
      "Steps must be an array",
      "Create a corrected plan"
    )
  end

  it "stops after the maximum number of attempts" do
    allow(llm_client)
      .to receive(:complete)
      .and_return('{"steps": "invalid"}')

    expect {
      generate_plan
    }.to raise_error(
      JobSearch::PlanningError,
      "Invalid LLM plan"
    )

    expect(llm_client)
      .to have_received(:complete).exactly(3).times
  end


it "repairs invalid tool arguments on the second attempt" do
  definition = JobSearch::ToolDefinition.new(
    name: :search_jobs,
    description: "Search for jobs",
    schema: {
      technology: String,
      remote: [ TrueClass, FalseClass ]
    }
  )

  catalog = JobSearch::ToolCatalog.new(
    definitions: [ definition ]
  )

  validated_planner = JobSearch::LlmPlanner.new(
    llm_client: llm_client,
    registry: registry,
    tool_catalog: catalog
  )

  invalid_response = JSON.generate(
    steps: [
      {
        name: "search",
        tool: "search_jobs",
        arguments: {
          technology: 123,
          remote: true
        },
        dependencies: []
      }
    ]
  )

  corrected_response = JSON.generate(
    steps: [
      {
        name: "search",
        tool: "search_jobs",
        arguments: {
          technology: "Ruby",
          remote: true
        },
        dependencies: []
      }
    ]
  )

  prompts = []

  allow(llm_client).to receive(:complete) do |prompt:|
    prompts << prompt

    prompts.length == 1 ? invalid_response : corrected_response
  end

  plan = retry_policy.call(objective: "Find Ruby jobs") do |context|
    validated_planner.plan(context: context)
  end

  expect(plan).to be_a(JobSearch::Plan)

  expect(plan.steps.first.action.arguments).to eq(
    technology: "Ruby",
    remote: true
  )

  expect(llm_client).to have_received(:complete).twice

  expect(prompts.last).to include(
    "This is planning attempt 2",
    "Invalid type for argument: technology",
    "Create a corrected plan"
  )
end
end

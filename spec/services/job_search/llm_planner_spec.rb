require "rails_helper"

RSpec.describe JobSearch::LlmPlanner do
  describe "#plan" do
    let(:objective) { "Encontrar vagas Ruby" }
    let(:llm_client) { instance_double(JobSearch::LlmClient) }
    let(:registry) { JobSearch::ToolRegistry.new }

    let(:tool_catalog) do
      JobSearch::ToolCatalog.new(
        definitions: [
          JobSearch::ToolDefinition.new(
            name: :search_jobs,
            description: "Search for job opportunities",
            arguments: { technology: "Technology", remote: "Remote only" },
            schema: { technology: String, remote: [ TrueClass, FalseClass ] }
          ),
          JobSearch::ToolDefinition.new(
            name: :candidate_profile,
            description: "Returns the candidate profile",
            arguments: {},
            schema: {}
          ),
          JobSearch::ToolDefinition.new(
            name: :analyze_jobs,
            description: "Analyzes jobs against the candidate profile",
            arguments: { jobs: "Jobs reference", profile: "Profile reference" },
            schema: { jobs: Array, profile: Hash },
            planning_schema: {
              jobs: JobSearch::ObservationReference,
              profile: JobSearch::ObservationReference
            }
          )
        ]
      )
    end

    let(:context) { JobSearch::PlanningContext.new(objective: objective) }
    let(:planner) do
      described_class.new(
        llm_client: llm_client,
        registry: registry,
        tool_catalog: tool_catalog
      )
    end

    let(:search_step) do
      {
        name: "search",
        tool: "search_jobs",
        arguments: { technology: "Ruby", remote: true },
        dependencies: []
      }
    end

    let(:profile_step) do
      { name: "profile", tool: "candidate_profile", arguments: {}, dependencies: [] }
    end

    let(:analyze_step) do
      {
        name: "analyze",
        tool: "analyze_jobs",
        arguments: {
          jobs: { "$ref": "search" },
          profile: { "$ref": "profile" }
        },
        dependencies: [ "search", "profile" ]
      }
    end

    before do
      registry.register(:search_jobs, JobSearch::SearchJobsTool)
      registry.register(:candidate_profile, JobSearch::CandidateProfileTool)
      registry.register(:analyze_jobs, JobSearch::AnalyzeJobsTool)
    end

    it "builds a plan from the LLM response" do
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(steps: [ search_step ]))

      plan = planner.plan(context: context)

      expect(plan).to be_a(JobSearch::Plan)
      expect(plan.steps.length).to eq(1)
      step = plan.steps.first
      expect(step.name).to eq(:search)
      expect(step.action.tool).to eq(:search_jobs)
      expect(step.action.arguments).to eq(technology: "Ruby", remote: true)
    end

    it "builds dependencies between steps" do
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(steps: [ search_step, profile_step, analyze_step ]))

      plan = planner.plan(context: context)
      analyze = plan.steps.find { |step| step.name == :analyze }

      expect(analyze.dependencies).to eq([ :search, :profile ])
    end

    it "sends the objective to the LLM" do
      allow(llm_client).to receive(:complete).and_return(JSON.generate(steps: []))

      planner.plan(context: context)

      expect(llm_client).to have_received(:complete) do |arguments|
        expect(arguments[:prompt]).to include(objective)
      end
    end

    it "rejects tools that are not registered" do
      invalid_step = {
        name: "hack", tool: "hack_the_planet", arguments: {}, dependencies: []
      }
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(steps: [ invalid_step ]))

      expect { planner.plan(context: context) }
        .to raise_error(JobSearch::PlanningError, "Invalid LLM plan")
    end

    it "converts references into ObservationReference objects" do
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(steps: [ search_step, profile_step, analyze_step ]))

      plan = planner.plan(context: context)
      analyze = plan.steps.find { |step| step.name == :analyze }
      jobs_reference = analyze.action.arguments[:jobs]
      profile_reference = analyze.action.arguments[:profile]

      expect(jobs_reference).to be_a(JobSearch::ObservationReference)
      expect(jobs_reference.step_name).to eq(:search)
      expect(profile_reference).to be_a(JobSearch::ObservationReference)
      expect(profile_reference.step_name).to eq(:profile)
    end

    it "includes the available tools in the prompt" do
      allow(llm_client).to receive(:complete).and_return(JSON.generate(steps: []))

      planner.plan(context: context)

      expect(llm_client).to have_received(:complete) do |arguments|
        prompt = arguments[:prompt]
        expect(prompt).to include("search_jobs")
        expect(prompt).to include("candidate_profile")
        expect(prompt).to include("analyze_jobs")
      end
    end

    it "validates the LLM output before building the plan" do
      output_validator = instance_double(JobSearch::PlanOutputValidator)
      allow(output_validator).to receive(:validate!).and_return(true)
      allow(llm_client).to receive(:complete).and_return(JSON.generate(steps: []))
      custom_planner = described_class.new(
        llm_client: llm_client,
        registry: registry,
        tool_catalog: tool_catalog,
        output_validator: output_validator
      )

      custom_planner.plan(context: context)

      expect(output_validator).to have_received(:validate!).with(steps: [])
    end

    it "rejects an invalid LLM plan structure" do
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(invalid: true))

      expect { planner.plan(context: context) }
        .to raise_error(JobSearch::PlanningError, "Invalid LLM plan")
    end

    it "rejects an LLM response with invalid steps type" do
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(steps: "invalid"))

      expect { planner.plan(context: context) }
        .to raise_error(JobSearch::PlanningError, "Invalid LLM plan")
    end

    it "wraps invalid JSON as a planning error" do
      allow(llm_client).to receive(:complete).and_return("this is not JSON")

      expect { planner.plan(context: context) }
        .to raise_error(JobSearch::PlanningError, "Invalid LLM plan")
    end

    it "preserves the original planning error cause" do
      allow(llm_client).to receive(:complete).and_return("invalid JSON")

      error = nil
      begin
        planner.plan(context: context)
      rescue JobSearch::PlanningError => raised_error
        error = raised_error
      end

      expect(error.cause).to be_a(JSON::ParserError)
    end

    it "plans using a planning context" do
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(steps: [ search_step ]))

      plan = planner.plan(context: context)

      expect(plan.steps.first.name).to eq(:search)
    end

    it "includes the previous planning error when repairing a plan" do
      original_error = ArgumentError.new(
        "Missing dependency for observation reference: analyze -> search"
      )
      planning_error = JobSearch::PlanningError.new(
        "Invalid LLM plan", cause: original_error
      )
      repair_context = JobSearch::PlanningContext.new(
        objective: objective, attempt: 2, previous_error: planning_error
      )
      allow(llm_client).to receive(:complete).and_return(JSON.generate(steps: []))

      planner.plan(context: repair_context)

      expect(llm_client).to have_received(:complete) do |arguments|
        prompt = arguments[:prompt]
        expect(prompt).to include("This is planning attempt 2")
        expect(prompt).to include("The previous plan was rejected")
        expect(prompt).to include(
          "Missing dependency for observation reference: analyze -> search"
        )
        expect(prompt).to include("Create a corrected plan")
      end
    end

    it "rejects invalid tool arguments during planning" do
      definition = JobSearch::ToolDefinition.new(
        name: :search_jobs,
        description: "Search for jobs",
        schema: { technology: String }
      )
      catalog = JobSearch::ToolCatalog.new(definitions: [ definition ])
      invalid_step = search_step.merge(arguments: { technology: 123 })
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(steps: [ invalid_step ]))
      custom_planner = described_class.new(
        llm_client: llm_client,
        registry: registry,
        tool_catalog: catalog
      )

      expect { custom_planner.plan(context: context) }
        .to raise_error(JobSearch::PlanningError, "Invalid LLM plan")
    end

    it "does not classify an internal LLM client error as a repairable plan" do
      allow(llm_client).to receive(:complete)
        .and_raise(ArgumentError, "Internal client configuration error")

      expect { planner.plan(context: context) }
        .to raise_error(ArgumentError, "Internal client configuration error")
    end

    it "does not retry unexpected internal validator errors" do
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(steps: [ search_step ]))
      validator = double("output_validator")
      allow(validator).to receive(:validate!)
        .and_raise(ArgumentError, "Internal validator bug")
      custom_planner = described_class.new(
        llm_client: llm_client,
        registry: registry,
        output_validator: validator
      )

      expect { custom_planner.plan(context: context) }
        .to raise_error(ArgumentError, "Internal validator bug")
    end

    it "repairs an invalid observation reference" do
      invalid_analyze = analyze_step.merge(
        arguments: {
          jobs: { "$ref": nil },
          profile: { "$ref": "profile" }
        }
      )
      invalid_response = JSON.generate(
        steps: [ search_step, profile_step, invalid_analyze ]
      )
      valid_response = JSON.generate(
        steps: [ search_step, profile_step, analyze_step ]
      )
      allow(llm_client).to receive(:complete)
        .and_return(invalid_response, valid_response)
      retry_policy = JobSearch::PlanningRetryPolicy.new(max_attempts: 3)

      plan = retry_policy.call(objective: objective) do |attempt_context|
        planner.plan(context: attempt_context)
      end

      expect(plan).to be_a(JobSearch::Plan)
      expect(llm_client).to have_received(:complete).twice
      analyze = plan.steps.find { |step| step.name == :analyze }
      expect(analyze.action.arguments[:jobs].step_name).to eq(:search)

      prompts = []
      expect(llm_client).to have_received(:complete).twice do |arguments|
        prompts << arguments[:prompt]
      end
      expect(prompts.last).to include("Invalid observation reference")
    end
  end

  describe "context budget" do
    let(:registry) { JobSearch::ToolRegistry.new }
    let(:llm_client) { instance_double(JobSearch::LlmClient) }

    before do
      registry.register(:search_jobs, JobSearch::SearchJobsTool)
      allow(llm_client).to receive(:complete)
        .and_return(JSON.generate(steps: []))
    end

    it "rejects an objective that is too large without calling the LLM" do
      planner = described_class.new(llm_client: llm_client, registry: registry)
      huge_objective = "Ruby " * 2_000

      expect do
        planner.plan(context: JobSearch::PlanningContext.new(objective: huge_objective))
      end.to raise_error(JobSearch::ContextBudgetExceeded)

      expect(llm_client).not_to have_received(:complete)
    end

    it "does not retry a context budget error" do
      planner = described_class.new(llm_client: llm_client, registry: registry)
      policy = JobSearch::PlanningRetryPolicy.new(max_attempts: 3)
      attempts = 0

      expect do
        policy.call(objective: "Ruby " * 2_000) do |context|
          attempts += 1
          planner.plan(context: context)
        end
      end.to raise_error(JobSearch::ContextBudgetExceeded)

      expect(attempts).to eq(1)
    end

    it "truncates a huge previous error in the repair prompt" do
      planner = described_class.new(llm_client: llm_client, registry: registry)
      previous_error = JobSearch::PlanningError.new(
        "Invalid LLM plan",
        cause: JobSearch::PlanValidationError.new("Unknown tool: #{'x' * 10_000}")
      )

      planner.plan(
        context: JobSearch::PlanningContext.new(
          objective: "Find Ruby jobs", attempt: 2, previous_error: previous_error
        )
      )

      expect(llm_client).to have_received(:complete) do |prompt:|
        expect(prompt).to include("...[truncated]")
        expect(prompt).to include("Objective:\nFind Ruby jobs")
        expect(prompt.length).to be < 4_000
      end
    end

    it "respects a custom context window" do
      planner = described_class.new(
        llm_client: llm_client,
        registry: registry,
        context_window: JobSearch::ContextWindow.new(max_input_tokens: 50)
      )

      expect do
        planner.plan(context: JobSearch::PlanningContext.new(objective: "Find Ruby jobs"))
      end.to raise_error(JobSearch::ContextBudgetExceeded)
    end
  end

  describe "planning history" do
    let(:registry) { JobSearch::ToolRegistry.new }
    let(:llm_client) { instance_double(JobSearch::LlmClient) }
    let(:planner) { described_class.new(llm_client: llm_client, registry: registry) }

    def rejected(message)
      JobSearch::PlanningError.new(
        "Invalid LLM plan",
        cause: JobSearch::PlanValidationError.new(message)
      )
    end

    before do
      registry.register(:search_jobs, JobSearch::SearchJobsTool)
      allow(llm_client).to receive(:complete).and_return(JSON.generate(steps: []))
    end

    it "omits the history section when there is no earlier rejection" do
      planner.plan(context: JobSearch::PlanningContext.new(objective: "Find Ruby jobs"))

      expect(llm_client).to have_received(:complete) do |prompt:|
        expect(prompt).not_to include("Earlier plans in this run")
      end
    end

    it "lists earlier rejections so the LLM does not repeat them" do
      context = JobSearch::PlanningContext.new(
        objective: "Find Ruby jobs",
        attempt: 3,
        previous_error: rejected("Cycle detected"),
        history: [ "Attempt 1: Unknown tool: foo" ]
      )

      planner.plan(context: context)

      expect(llm_client).to have_received(:complete) do |prompt:|
        expect(prompt).to include("Earlier plans in this run were also rejected")
        expect(prompt).to include("- Attempt 1: Unknown tool: foo")
        expect(prompt).to include("Reason:\nCycle detected")
        expect(prompt.index("Earlier plans")).to be < prompt.index("This is planning attempt 3")
      end
    end

    it "includes lessons from previous runs" do
      context = JobSearch::PlanningContext.new(
        objective: "Find Ruby jobs", lessons: [ "Unknown tool: linkedin_search" ]
      )

      planner.plan(context: context)

      expect(llm_client).to have_received(:complete) do |prompt:|
        expect(prompt).to include("rejected in previous runs")
        expect(prompt).to include("- Unknown tool: linkedin_search")
      end
    end

    it "omits the lessons section when there are none" do
      planner.plan(context: JobSearch::PlanningContext.new(objective: "Find Ruby jobs"))

      expect(llm_client).to have_received(:complete) do |prompt:|
        expect(prompt).not_to include("previous runs")
      end
    end

    it "keeps the history inside its token limit" do
      history = Array.new(50) { |i| "Attempt #{i}: #{'x' * 400}" }
      context = JobSearch::PlanningContext.new(
        objective: "Find Ruby jobs", attempt: 3,
        previous_error: rejected("Cycle detected"), history: history
      )

      planner.plan(context: context)

      expect(llm_client).to have_received(:complete) do |prompt:|
        history_text = prompt[prompt.index("Earlier plans")...prompt.index("This is planning attempt")]
        expect(JobSearch::TokenEstimator.new.count(history_text))
          .to be <= described_class::MAX_HISTORY_TOKENS + 1
      end
    end
  end

  describe "malformed observation references" do
    let(:registry) do
      JobSearch::ToolRegistry.new.tap do |tool_registry|
        tool_registry.register(:search_jobs, JobSearch::SearchJobsTool)
        tool_registry.register(:analyze_jobs, JobSearch::AnalyzeJobsTool)
      end
    end

    it "rejects observation references with extra fields" do
      response = JSON.generate(
        steps: [
          {
            name: "search",
            tool: "search_jobs",
            arguments: { technology: "Ruby", remote: true },
            dependencies: []
          },
          {
            name: "analyze",
            tool: "analyze_jobs",
            arguments: {
              jobs: { "$ref" => "search", "unexpected" => "value" },
              profile: { "$ref" => "search" }
            },
            dependencies: [ "search" ]
          }
        ]
      )

      llm_client = double("llm_client")
      allow(llm_client).to receive(:complete).and_return(response)
      planner = described_class.new(llm_client: llm_client, registry: registry)
      context = JobSearch::PlanningContext.new(
        objective: "Find Ruby jobs", attempt: 1, previous_error: nil
      )

      expect { planner.plan(context: context) }
        .to raise_error(JobSearch::PlanningError, "Invalid LLM plan")
    end

    [ nil, "", 123 ].each do |invalid_reference|
      it "rejects reference #{invalid_reference.inspect}" do
        response = JSON.generate(
          steps: [
            {
              name: "search",
              tool: "search_jobs",
              arguments: { value: { "$ref" => invalid_reference } },
              dependencies: []
            }
          ]
        )
        llm_client = double("llm_client")
        allow(llm_client).to receive(:complete).and_return(response)
        planner = described_class.new(llm_client: llm_client, registry: registry)
        context = JobSearch::PlanningContext.new(
          objective: "Find Ruby jobs", attempt: 1, previous_error: nil
        )

        expect { planner.plan(context: context) }
          .to raise_error(JobSearch::PlanningError, "Invalid LLM plan")
      end
    end
  end
end

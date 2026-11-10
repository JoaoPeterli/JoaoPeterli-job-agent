
require "rails_helper"

RSpec.describe "JobSearch Plan Repair" do
  describe "planning recovery" do
    it "repairs an invalid plan and completes the execution" do
      prompts = []
      llm_calls = 0

      llm_client = instance_double(
        JobSearch::LlmClient
      )

      allow(llm_client)
        .to receive(:complete) do |prompt:|
          prompts << prompt
          llm_calls += 1

          if llm_calls == 1
            JSON.generate(
              {
                steps: [
                  {
                    name: "search",
                    tool: "search_jobs",
                    arguments: {
                      technology: "Ruby",
                      remote: true
                    },
                    dependencies: []
                  },
                  {
                    name: "profile",
                    tool: "candidate_profile",
                    arguments: {},
                    dependencies: []
                  },
                  {
                    name: "analyze",
                    tool: "analyze_jobs",
                    arguments: {
                      jobs: {
                        "$ref": "search"
                      },
                      profile: {
                        "$ref": "profile"
                      }
                    },

                    # ERRO PROPOSITAL:
                    # analyze usa search e profile,
                    # mas não declara as dependências.
                    dependencies: []
                  }
                ]
              }
            )
          else
            JSON.generate(
              {
                steps: [
                  {
                    name: "search",
                    tool: "search_jobs",
                    arguments: {
                      technology: "Ruby",
                      remote: true
                    },
                    dependencies: []
                  },
                  {
                    name: "profile",
                    tool: "candidate_profile",
                    arguments: {},
                    dependencies: []
                  },
                  {
                    name: "analyze",
                    tool: "analyze_jobs",
                    arguments: {
                      jobs: {
                        "$ref": "search"
                      },
                      profile: {
                        "$ref": "profile"
                      }
                    },
                    dependencies: [
                      "search",
                      "profile"
                    ]
                  }
                ]
              }
            )
          end
        end

      registry = JobSearch::ToolRegistry.new

      registry.register(
        :search_jobs,
        JobSearch::SearchJobsTool
      )

      registry.register(
        :candidate_profile,
        JobSearch::CandidateProfileTool
      )

      registry.register(
        :analyze_jobs,
        JobSearch::AnalyzeJobsTool
      )

      tool_catalog = JobSearch::ToolCatalog.new(
        definitions: [
          JobSearch::ToolDefinition.new(
            name: :search_jobs,
            description: "Search for job opportunities",
            side_effects: false,
            arguments: {
              technology: "Technology",
              remote: "Remote only"
            },
            schema: {
              technology: String,
              remote: [
                TrueClass,
                FalseClass
              ]
            }
          ),

          JobSearch::ToolDefinition.new(
            name: :candidate_profile,
            description: "Returns the candidate profile",
            side_effects: false,
            arguments: {},
            schema: {}
          ),

          JobSearch::ToolDefinition.new(
            name: :analyze_jobs,
            description: "Analyzes jobs against the candidate profile",
            side_effects: false,
            arguments: {
              jobs: "Jobs reference",
              profile: "Profile reference"
            },
            schema: {
              jobs: Array,
              profile: Hash
            },
            planning_schema: {
              jobs: JobSearch::ObservationReference,
              profile: JobSearch::ObservationReference
            }
          )
        ]
      )

      planner = JobSearch::LlmPlanner.new(
        llm_client: llm_client,
        registry: registry,
        tool_catalog: tool_catalog
      )

      retry_policy = JobSearch::RetryPolicy.new(
        max_attempts: 3,
        backoff_strategy: JobSearch::BackoffStrategy.new(
          base_delay: 0
        ),
        sleeper: JobSearch::Sleeper.new
      )

      execution_budget = JobSearch::ExecutionBudget.new(
        max_steps: 10,
        max_tool_calls: 20
      )

      timeout_policy = JobSearch::TimeoutPolicy.new(
        timeout_seconds: 5
      )

      # NOVO: store compartilhado durante esta execução.
      idempotency_store = JobSearch::IdempotencyStore.new

      idempotency_policy = JobSearch::IdempotencyPolicy.new(
        store: idempotency_store
      )

      executor = JobSearch::Executor.new(
        registry: registry,
        retry_policy: retry_policy,
        tool_catalog: tool_catalog,
        tool_validator: JobSearch::ToolValidator.new,
        execution_budget: execution_budget,
        timeout_policy: timeout_policy,
        idempotency_policy: idempotency_policy
      )

      plan_executor = JobSearch::PlanExecutor.new(
        executor: executor,
        execution_budget: execution_budget,
        tool_catalog: tool_catalog
      )

      planning_retry_policy =
        JobSearch::PlanningRetryPolicy.new(
          max_attempts: 3
        )

      agent = JobSearch::Agent.new(
        objective: "Encontrar vagas Ruby",
        planner: planner,
        plan_executor: plan_executor,
        planning_retry_policy: planning_retry_policy
      )

      state = agent.run

      expect(llm_calls).to eq(2)
      expect(prompts.length).to eq(2)

      expect(prompts.first).not_to include(
        "The previous plan was rejected"
      )

      expect(prompts.last).to include(
        "This is planning attempt 2"
      )

      expect(prompts.last).to include(
        "The previous plan was rejected"
      )

      expect(prompts.last).to include(
        "Create a corrected plan"
      )

      expect(state.status).to eq(:completed)

      expect(
        state.observation_for(:search)
      ).to be_an(Array)

      expect(
        state.observation_for(:profile)
      ).to be_a(Hash)

      expect(
        state.observation_for(:analyze)
      ).to be_an(Array)

      # NOVO: verifica que os três Steps foram concluídos
      # e armazenados no IdempotencyStore.
      expect(
        idempotency_store.completed?("#{state.run_id}:search")
      ).to eq(true)

      expect(
        idempotency_store.completed?("#{state.run_id}:profile")
      ).to eq(true)

      expect(
        idempotency_store.completed?("#{state.run_id}:analyze")
      ).to eq(true)
    end
  end
end

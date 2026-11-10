require "rails_helper"
require Rails.root.join("spec/support/job_search/scripted_llm_client")

# Avaliação de saídas do LLM: cada fixture em spec/fixtures/llm/plans é
# uma resposta que o LLM pode produzir. A tabela abaixo diz o que o
# planner deve fazer com ela. Ao encontrar uma resposta problemática em
# produção, salve-a como fixture e adicione a expectativa aqui.
RSpec.describe "LLM plan output evaluation" do
  def fixtures_dir
    Rails.root.join("spec/fixtures/llm/plans")
  end

  expectations = {
    "valid_full_plan.json" => { steps: [ :search, :profile, :analyze ] },
    "valid_search_only.json" => { steps: [ :search ] },
    "unknown_tool.json" => { error: "Unknown tool: linkedin_search" },
    "missing_dependency.json" => { error: "Missing dependency for observation reference: analyze -> search" },
    "invalid_reference.json" => { error: "Invalid observation reference: expected non-empty String" },
    "wrong_argument_type.json" => { error: "Invalid type for argument: remote" },
    "cyclic_dependencies.json" => { error: "Cycle detected" },
    "missing_steps.json" => { error: "Plan output must contain steps" },
    "truncated_json.json" => { error: /unexpected end of input/ }
  }.freeze

  define_method(:expectations) { expectations }

  def plan_with(fixture)
    llm_client = JobSearch::ScriptedLlmClient.new([ File.read(fixtures_dir.join(fixture)) ])
    planner = JobSearch::Container.new(llm_client: llm_client).send(:planner)

    planner.plan(context: JobSearch::PlanningContext.new(objective: "Encontrar vagas Ruby"))
  end

  it "has an expectation for every fixture" do
    fixtures = Dir[fixtures_dir.join("*.json")].map { |path| File.basename(path) }.sort

    expect(fixtures).to eq(expectations.keys.sort)
  end

  expectations.each do |fixture, expectation|
    if expectation.key?(:steps)
      it "accepts #{fixture}" do
        expect(plan_with(fixture).steps.map(&:name)).to eq(expectation[:steps])
      end
    else
      it "rejects #{fixture} as a repairable plan" do
        expect { plan_with(fixture) }.to raise_error(JobSearch::PlanningError) { |error|
          expect(error).to be_retryable
          expect(error.cause.message).to match(expectation[:error])
        }
      end
    end
  end
end

require "rails_helper"
require Rails.root.join("spec/support/job_search/scripted_llm_client")

# Snapshot do prompt de planejamento. Qualquer mudança no texto enviado
# ao LLM (regras, descrição de ferramentas, seções) quebra este teste,
# para que mudanças de prompt sejam sempre intencionais e revisadas.
#
# Para aceitar uma mudança intencional:
#   UPDATE_SNAPSHOTS=1 bundle exec rspec spec/evals/plan_prompt_snapshot_spec.rb
RSpec.describe "Planning prompt snapshot" do
  def snapshots_dir
    Rails.root.join("spec/fixtures/llm/prompts")
  end

  def prompt_for(context)
    llm_client = JobSearch::ScriptedLlmClient.new([ JSON.generate(steps: []) ])
    planner = JobSearch::Container.new(llm_client: llm_client).send(:planner)

    planner.plan(context: context)

    llm_client.prompts.last
  end

  def match_snapshot(name, actual)
    path = snapshots_dir.join("#{name}.txt")

    File.write(path, actual) if ENV["UPDATE_SNAPSHOTS"] == "1"

    unless path.exist?
      raise "Missing snapshot #{path}. Run with UPDATE_SNAPSHOTS=1 to create it."
    end

    expect(actual).to eq(File.read(path)),
                      "Prompt #{name} changed. If intentional, run with UPDATE_SNAPSHOTS=1."
  end

  it "keeps the initial planning prompt stable" do
    context = JobSearch::PlanningContext.new(objective: "Encontrar vagas Ruby remotas")

    match_snapshot("initial_plan", prompt_for(context))
  end

  it "keeps the repair prompt stable" do
    previous_error = JobSearch::PlanningError.new(
      "Invalid LLM plan",
      cause: JobSearch::PlanValidationError.new("Cycle detected")
    )
    context = JobSearch::PlanningContext.new(
      objective: "Encontrar vagas Ruby remotas",
      attempt: 3,
      previous_error: previous_error,
      history: [ "Attempt 1: Unknown tool: linkedin_search" ],
      lessons: [ "Invalid type for argument: remote" ]
    )

    match_snapshot("repair_plan", prompt_for(context))
  end
end

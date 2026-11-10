require "rails_helper"
require Rails.root.join("spec/support/job_search/scripted_llm_client")

# Fluxo completo com a montagem real do Container (planner, validação,
# executor, ferramentas, memória persistente); só o LLM é roteirizado.
RSpec.describe "Agent end to end" do
  def fixtures_dir
    Rails.root.join("spec/fixtures/llm/plans")
  end

  def fixture(name)
    File.read(fixtures_dir.join(name))
  end

  def run_agent(objective, responses)
    llm_client = JobSearch::ScriptedLlmClient.new(responses)
    agent = JobSearch::Container.new(llm_client: llm_client).agent(objective: objective)

    [ agent, llm_client ]
  end

  it "plans, executes and analyzes jobs" do
    agent, llm_client = run_agent("Encontrar vagas Ruby remotas", [ fixture("valid_full_plan.json") ])

    state = agent.run

    expect(state.status).to eq(:completed)
    expect(llm_client.calls).to eq(1)
    expect(state.step_statuses).to eq(search: :completed, profile: :completed, analyze: :completed)
    expect(state.observation_for(:analyze)).to eq([
      { title: "Senior Ruby Developer", company: "Example Company", remote: true, score: 40 }
    ])
  end

  it "repairs an invalid plan before executing" do
    agent, llm_client = run_agent(
      "Encontrar vagas Ruby remotas",
      [ fixture("missing_dependency.json"), fixture("valid_full_plan.json") ]
    )

    state = agent.run

    expect(state.status).to eq(:completed)
    expect(llm_client.prompts.last)
      .to include("Missing dependency for observation reference: analyze -> search")
  end

  it "asks for a smaller plan after a truncated response" do
    truncated = JobSearch::LlmResponse.new(
      text: fixture("truncated_json.json"),
      status: :incomplete,
      incomplete_reason: :max_output_tokens
    )
    agent, llm_client = run_agent("Encontrar vagas Ruby remotas", [ truncated, fixture("valid_search_only.json") ])

    expect(agent.run.status).to eq(:completed)
    expect(llm_client.prompts.last).to include("Create a smaller plan")
  end

  it "stops without retrying when the model refuses" do
    refusal = JobSearch::LlmResponse.new(text: "", refusal: "I can't help with that.")
    agent, llm_client = run_agent("Encontrar vagas Ruby remotas", [ refusal ])

    expect { agent.run }.to raise_error(JobSearch::LlmRefusalError)
    expect(llm_client.calls).to eq(1)
  end

  it "gives up after the planning attempts are exhausted" do
    agent, llm_client = run_agent("Encontrar vagas Ruby remotas", Array.new(3) { fixture("unknown_tool.json") })

    expect { agent.run }.to raise_error(JobSearch::PlanningError, "Invalid LLM plan")
    expect(llm_client.calls).to eq(3)
  end

  it "persists the run memory" do
    agent, = run_agent(
      "Encontrar vagas Ruby remotas",
      [ fixture("unknown_tool.json"), fixture("valid_full_plan.json") ]
    )

    state = agent.run

    kinds = AgentMemoryEntry.where(run_id: state.run_id).order(:seq).pluck(:kind)
    expect(kinds).to eq(%w[
      plan_rejected plan_started step_completed step_completed step_completed run_finished
    ])
  end

  it "uses lessons from a previous run with a similar objective" do
    first_agent, = run_agent(
      "Encontrar vagas Ruby remotas",
      [ fixture("unknown_tool.json"), fixture("valid_full_plan.json") ]
    )
    first_agent.run

    second_agent, llm_client = run_agent("Vagas remotas de Ruby", [ fixture("valid_full_plan.json") ])
    second_agent.run

    expect(llm_client.prompts.first).to include("rejected in previous runs")
    expect(llm_client.prompts.first).to include("- Unknown tool: linkedin_search")
  end
end

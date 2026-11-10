require "rails_helper"

RSpec.describe JobSearch::LlmPlanner, "reflections (ReAct)" do
  let(:llm) do
    Class.new do
      attr_reader :prompts

      def initialize = @prompts = []

      def complete(prompt:)
        @prompts << prompt
        '{"steps":[{"name":"search","tool":"search_jobs","arguments":{"technology":"Ruby","remote":true},"dependencies":[]}]}'
      end
    end.new
  end
  let(:registry) { JobSearch::ToolRegistry.new.tap { |registry| registry.register(:search_jobs, JobSearch::SearchJobsTool) } }

  it "puts the earlier iterations and the reviewer guidance in the prompt as untrusted data" do
    context = JobSearch::PlanningContext.new(
      objective: "Vagas Rails",
      reflections: [ "Iteration 1: searched \"Ruby on Rails\" (remote); 1 jobs found. Reviewer guidance: Search Ruby instead." ]
    )

    described_class.new(llm_client: llm, registry: registry).plan(context: context)

    prompt = llm.prompts.sole
    expect(prompt).to include('<untrusted_input source="agent_reflection">', "Reviewer guidance: Search Ruby instead.",
                              "Do not repeat a search with the same arguments")
  end

  it "has no reflections section on the first iteration" do
    described_class.new(llm_client: llm, registry: registry).plan(context: JobSearch::PlanningContext.new(objective: "Vagas Rails"))

    expect(llm.prompts.sole).not_to include("agent_reflection")
  end
end

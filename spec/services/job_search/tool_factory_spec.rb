require "rails_helper"

RSpec.describe JobSearch::ToolFactory do
  it "builds a new tool on every execution" do
    factory = described_class.new { Object.new }

    expect(factory.new).not_to be(factory.new)
  end

  describe "the analyze_jobs registration in the Container" do
    def analyze_tool(container) = container.send(:registry).fetch(:analyze_jobs).new

    it "has no LLM evaluator when the feature is off (tests) or an LLM client is injected" do
      expect(analyze_tool(JobSearch::Container.new).instance_variable_get(:@evaluator)).to be_nil

      allow(Rails.configuration.x).to receive(:llm_job_evaluation).and_return(true)
      injected = JobSearch::Container.new(llm_client: instance_double(JobSearch::LlmClient))
      expect(analyze_tool(injected).instance_variable_get(:@evaluator)).to be_nil
    end

    it "gets a metered LLM evaluator when the feature is on" do
      allow(Rails.configuration.x).to receive(:llm_job_evaluation).and_return(true)
      allow(OpenAI::Client).to receive(:new).and_return(double("OpenAI::Client"))

      evaluator = analyze_tool(JobSearch::Container.new).instance_variable_get(:@evaluator)

      expect(evaluator).to be_a(JobSearch::JobEvaluator)
      expect(evaluator.instance_variable_get(:@llm_client)).to be_a(JobSearch::MeteredLlmClient)
    end

    it "adds the vector index and the RAG memory when RAG is on" do
      allow(Rails.configuration.x).to receive_messages(llm_job_evaluation: true, rag_enabled: true)
      allow(OpenAI::Client).to receive(:new).and_return(double("OpenAI::Client"))

      tool = analyze_tool(JobSearch::Container.new)

      expect(tool.instance_variable_get(:@indexer)).to be_a(JobSearch::JobIndex)
      expect(tool.instance_variable_get(:@evaluator).instance_variable_get(:@memory)).to be_a(JobSearch::PreferenceMemory)
    end

    it "gives the reflector (ReAct) only to the single agent, when enabled" do
      allow(Rails.configuration.x).to receive(:react_enabled).and_return(true)
      allow(OpenAI::Client).to receive(:new).and_return(double("OpenAI::Client"))
      container = JobSearch::Container.new

      expect(container.agent(objective: "x").instance_variable_get(:@reflector)).to be_a(JobSearch::Reflector)
      expect(container.agent(objective: "x", profile: JobSearch::AgentProfiles::RESEARCHER).instance_variable_get(:@reflector)).to be_nil
    end
  end
end

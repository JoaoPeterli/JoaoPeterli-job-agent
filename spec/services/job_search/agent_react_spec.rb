require "rails_helper"

RSpec.describe JobSearch::Agent, "ReAct loop" do
  let(:ref) { ->(name) { JobSearch::ObservationReference.new(step_name: name) } }
  let(:audit_trail) { instance_double(JobSearch::AuditTrail, record: nil) }

  def plan_for(technology, remote: true)
    JobSearch::Plan.new(steps: [
      JobSearch::Step.new(name: :search, action: JobSearch::AgentAction.new(tool: :search_jobs, arguments: { technology: technology, remote: remote })),
      JobSearch::Step.new(name: :analyze, dependencies: [ :search ],
                          action: JobSearch::AgentAction.new(tool: :analyze_jobs, arguments: { jobs: ref.(:search) }))
    ])
  end

  # Planner falso: devolve os planos em ordem e guarda os contextos recebidos.
  let(:planner) do
    Class.new do
      attr_reader :contexts

      def initialize(plans) = (@plans = plans) && (@contexts = [])

      def plan(context:)
        @contexts << context
        @plans.shift
      end
    end
  end

  # Executor falso: a busca "acha" as vagas do roteiro; a análise dá a nota do roteiro.
  def executor(results, failing = {})
    executor = instance_double(JobSearch::PlanExecutor)
    allow(executor).to receive(:execute) do |plan:, state:|
      plan.steps.each do |step|
        raise failing[step.name] if failing[step.name]

        state.start_step!(step.name, tool: step.action.tool)
        jobs = results.fetch(plan.steps.first.action.arguments[:technology])
        state.add_observation(step.name, jobs)
        state.complete_step!(step.name)
      end
      state.complete!
    end
    executor
  end

  def reflector(*reflections, max_iterations: 3)
    reflector = instance_double(JobSearch::Reflector, max_iterations: max_iterations)
    allow(reflector).to receive(:reflect).and_return(*reflections)
    reflector
  end

  def agent(planner:, executor:, reflector:)
    described_class.new(objective: "Vagas Ruby on Rails sênior", planner: planner, plan_executor: executor,
                        planning_retry_policy: JobSearch::PlanningRetryPolicy.new(max_attempts: 2),
                        audit_trail: audit_trail, reflector: reflector)
  end

  let(:few) { [ { title: "Rails Dev", company: "A", score: 40 } ] }
  let(:more) { [ { title: "Ruby Engineer", company: "B", score: 80 }, { title: "Rails Dev", company: "A", score: 60 } ] }
  let(:search_again) do
    JobSearch::Reflection.new(decision: "search_again", reason: "Poucas vagas.", guidance: "Search Ruby instead.", by: "llm")
  end

  it "finishes after one iteration when the reflector says so" do
    planner = self.planner.new([ plan_for("Ruby on Rails") ])

    state = agent(planner: planner, executor: executor({ "Ruby on Rails" => more }), reflector: reflector(JobSearch::Reflection.finish("ok"))).run

    expect(planner.contexts.size).to eq(1)
    expect(state.iterations).to contain_exactly(hash_including(iteration: 1, jobs_found: 2, strong_matches: 1, decision: "finish"))
    expect(JobSearch::AgentOutput.from(state)).to eq(more)
  end

  it "searches again following the guidance and merges the jobs of every iteration" do
    planner = self.planner.new([ plan_for("Ruby on Rails"), plan_for("Ruby") ])
    reflector = reflector(search_again, JobSearch::Reflection.finish("Bom resultado.", by: "llm"))

    state = agent(planner: planner, executor: executor({ "Ruby on Rails" => few, "Ruby" => more }), reflector: reflector).run

    expect(planner.contexts.last.reflections)
      .to eq([ "Iteration 1: searched \"Ruby on Rails\" (remote); 1 jobs found, 0 strong matches (score >= 70). Reviewer guidance: Search Ruby instead." ])
    expect(state.step_statuses.keys).to eq(%i[search analyze i2_search i2_analyze])
    expect(state.iterations.map { |it| it[:decision] }).to eq(%w[search_again finish])
    # "Rails Dev" foi achada nas duas iterações: fica uma vez, com a maior nota.
    expect(JobSearch::AgentOutput.from(state)).to contain_exactly(
      { title: "Rails Dev", company: "A", score: 60 }, { title: "Ruby Engineer", company: "B", score: 80 }
    )
    expect(audit_trail).to have_received(:record).with(hash_including(event: "agent.reflection")).twice
  end

  it "stops without executing when the new plan repeats a search already done" do
    planner = self.planner.new([ plan_for("Ruby on Rails"), plan_for("ruby on rails ") ])
    executor = executor({ "Ruby on Rails" => few })

    state = agent(planner: planner, executor: executor, reflector: reflector(search_again)).run

    expect(executor).to have_received(:execute).once
    expect(state.iterations.last).to include(iteration: 2, decision: "finish", reason: /repetia uma busca/)
  end

  it "keeps the previous result when a later iteration fails" do
    planner = self.planner.new([ plan_for("Ruby on Rails"), plan_for("Ruby") ])
    executor = executor({ "Ruby on Rails" => few, "Ruby" => more }, { i2_search: JobSearch::ToolTimeoutError.new("slow") })

    state = agent(planner: planner, executor: executor, reflector: reflector(search_again)).run

    expect(state.status).to eq(:completed)
    expect(JobSearch::AgentOutput.from(state)).to eq(few)
    expect(state.iterations.last).to include(reason: /Iteração 2 falhou \(ToolTimeoutError\)/)
  end

  it "always stops on cancellation or deadline" do
    planner = self.planner.new([ plan_for("Ruby on Rails"), plan_for("Ruby") ])
    executor = executor({ "Ruby on Rails" => few, "Ruby" => more }, { i2_search: JobSearch::RunCancelled.new("stop") })

    expect { agent(planner: planner, executor: executor, reflector: reflector(search_again)).run }
      .to raise_error(JobSearch::RunCancelled)
  end

  it "finishes with what it has when the reflector fails" do
    planner = self.planner.new([ plan_for("Ruby on Rails") ])
    reflector = instance_double(JobSearch::Reflector, max_iterations: 3)
    allow(reflector).to receive(:reflect).and_raise(JobSearch::ReflectionError, "bad json")

    state = agent(planner: planner, executor: executor({ "Ruby on Rails" => few }), reflector: reflector).run

    expect(state.iterations.sole).to include(decision: "finish", reason: /Reflexão indisponível/)
  end
end

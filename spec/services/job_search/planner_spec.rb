require "rails_helper"

RSpec.describe JobSearch::Planner do
  describe "#plan" do
    it "creates a plan for searching, loading profile and analyzing jobs" do
      planner = described_class.new

      plan = planner.plan(
        objective: "Encontrar vagas Ruby remotas"
      )

      expect(plan).to be_a(
        JobSearch::Plan
      )

      expect(
        plan.steps.map(&:name)
      ).to eq(
        [ :search, :profile, :analyze ]
      )

      search = plan.steps.find do |step|
        step.name == :search
      end

      profile = plan.steps.find do |step|
        step.name == :profile
      end

      analyze = plan.steps.find do |step|
        step.name == :analyze
      end

      expect(search.action.tool)
        .to eq(:search_jobs)

      expect(profile.action.tool)
        .to eq(:candidate_profile)

      expect(analyze.action.tool)
        .to eq(:analyze_jobs)

      expect(search.dependencies)
        .to eq([])

      expect(profile.dependencies)
        .to eq([])

      expect(analyze.dependencies)
        .to eq([ :search, :profile ])

      jobs_reference =
        analyze.action.arguments[:jobs]

      profile_reference =
        analyze.action.arguments[:profile]

      expect(jobs_reference)
        .to be_a(
          JobSearch::ObservationReference
        )

      expect(jobs_reference.step_name)
        .to eq(:search)

      expect(profile_reference)
        .to be_a(
          JobSearch::ObservationReference
        )

      expect(profile_reference.step_name)
        .to eq(:profile)
    end
  end
end

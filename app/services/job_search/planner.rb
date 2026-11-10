module JobSearch
  class Planner
    def plan(objective:)
      search_action = AgentAction.new(
        tool: :search_jobs,
        arguments: {
          technology: "Ruby",
          remote: true
        }
      )

      profile_action = AgentAction.new(
        tool: :candidate_profile
      )

      analyze_action = AgentAction.new(
        tool: :analyze_jobs,
        arguments: {
          jobs: ObservationReference.new(
            step_name: :search
          ),

          profile: ObservationReference.new(
            step_name: :profile
          )
        }
      )

      search_step = Step.new(
        name: :search,
        action: search_action
      )

      profile_step = Step.new(
        name: :profile,
        action: profile_action
      )

      analyze_step = Step.new(
        name: :analyze,
        action: analyze_action,
        dependencies: [
          :search,
          :profile
        ]
      )

      Plan.new(
        steps: [
          search_step,
          profile_step,
          analyze_step
        ]
      )
    end
  end
end

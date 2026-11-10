module JobSearch
  class ObservationReference
    attr_reader :step_name

    def initialize(step_name:)
      @step_name = step_name
    end
  end
end

module JobSearch
  class Step
    attr_reader :name, :action, :dependencies

    def initialize(name:, action:, dependencies: [])
      @name = name
      @action = action
      @dependencies = dependencies
    end

    def ready?(completed_steps)
      dependencies.all? do |dependency|
        completed_steps.include?(dependency)
      end
    end
  end
end

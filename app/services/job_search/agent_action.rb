module JobSearch
  class AgentAction
    attr_reader :tool, :arguments

    def initialize(tool:, arguments: {})
      @tool = tool
      @arguments = arguments
    end
  end
end

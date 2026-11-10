module JobSearch
  class ToolRegistry
    def initialize
      @tools = {}
    end

    def register(name, tool)
      @tools[name] = tool
    end

    def fetch(name)
      @tools.fetch(name)
    end

    def registered?(name)
      @tools.key?(name)
    end
  end
end

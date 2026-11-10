module JobSearch
  # Ação com efeito colateral sem aprovação humana para estes argumentos.
  class ApprovalRequiredError < ToolAuthorizationError
    attr_reader :tool, :fingerprint

    def initialize(message, tool:, fingerprint:)
      super(message)
      @tool = tool
      @fingerprint = fingerprint
    end
  end
end

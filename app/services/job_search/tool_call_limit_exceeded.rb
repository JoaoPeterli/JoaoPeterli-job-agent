module JobSearch
  # A ferramenta já foi usada o máximo de vezes permitido no run.
  class ToolCallLimitExceeded < ToolAuthorizationError; end
end

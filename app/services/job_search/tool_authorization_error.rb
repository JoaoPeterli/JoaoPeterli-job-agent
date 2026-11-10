module JobSearch
  # Uma ação foi barrada pela política de ferramentas. É permanente:
  # repetir a mesma chamada não muda a decisão.
  class ToolAuthorizationError < PermanentError; end
end

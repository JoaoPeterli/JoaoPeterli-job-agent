module JobSearch
  class LlmClient
    def complete(prompt:)
      raise NotImplementedError,
            "Subclasses must implement #complete"
    end
  end
end

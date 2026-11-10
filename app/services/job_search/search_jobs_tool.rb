module JobSearch
  class SearchJobsTool
    def call(technology:, remote:)
      [
        {
          title: "Senior #{technology} Developer",
          company: "Example Company",
          remote: remote
        }
      ]
    end
  end
end

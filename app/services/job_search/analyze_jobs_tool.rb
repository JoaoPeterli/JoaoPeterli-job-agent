module JobSearch
  class AnalyzeJobsTool
    def call(jobs:, profile:)
      jobs.map do |job|
        job.merge(
          score: calculate_score(
            job,
            profile
          )
        )
      end
    end

    private

    def calculate_score(job, profile)
      score = 0

      profile[:skills].each do |skill|
        if job[:title]&.include?(skill)
          score += 20
        end
      end

      if job[:remote] && profile[:remote]
        score += 20
      end

      score
    end
  end
end

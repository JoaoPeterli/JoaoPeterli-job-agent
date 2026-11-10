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

      # Cada skill do perfil vale 20 se aparecer no título ou nas tags da
      # vaga, como palavra inteira e sem diferenciar maiúsculas.
      text = ([ job[:title] ] + Array(job[:tags])).compact.join(" | ")

      profile[:skills].each do |skill|
        score += 20 if text.match?(/(?<![[:alnum:]])#{Regexp.escape(skill)}(?![[:alnum:]])/i)
      end

      if job[:remote] && profile[:remote]
        score += 20
      end

      score
    end
  end
end

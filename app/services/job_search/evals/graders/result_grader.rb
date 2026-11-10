module JobSearch
  module Evals
    module Graders
      # O resultado final serve para o usuário?
      #
      # - min_results: quantidade mínima de vagas
      # - result_relevance: fração de vagas cujo título cita uma das
      #   tecnologias pedidas (passa com >= RELEVANCE_THRESHOLD)
      class ResultGrader
        RELEVANCE_THRESHOLD = 0.8

        def grade(eval_case, run)
          return [] unless eval_case.expected_outcome == "completed"

          jobs = Array(run.output).select { |item| item.is_a?(Hash) }
          checks = []
          checks << min_results(eval_case.expect[:min_results], jobs) if eval_case.expect.key?(:min_results)
          checks << relevance(eval_case.expect[:technologies], jobs) if eval_case.expect.key?(:technologies)
          checks
        end

        private

        def min_results(minimum, jobs)
          return Check.pass(:min_results, "#{jobs.size} jobs") if jobs.size >= minimum

          Check.fail(:min_results, "#{jobs.size} jobs, expected at least #{minimum}")
        end

        def relevance(technologies, jobs)
          return Check.fail(:result_relevance, "no jobs to evaluate") if jobs.empty?

          relevant = jobs.count do |job|
            technologies.any? { |tech| job[:title].to_s.downcase.include?(tech.to_s.downcase) }
          end
          score = (relevant.to_f / jobs.size).round(4)
          detail = "#{relevant}/#{jobs.size} jobs mention #{technologies.join(' or ')}"

          return Check.pass(:result_relevance, detail, score: score) if score >= RELEVANCE_THRESHOLD

          Check.fail(:result_relevance, detail, score: score)
        end
      end
    end
  end
end

module JobSearch
  module Evals
    module Graders
      # A trajetória faz sentido para o objetivo? (sem olhar o resultado)
      #
      # - technologies: cada tecnologia pedida foi buscada (crédito parcial)
      # - remote: todas as buscas usaram o filtro remoto esperado
      # - no_redundant_calls: nenhuma chamada repetida com os mesmos args
      class ToolUseGrader
        def grade(eval_case, run)
          return [] unless run.status == :completed || run.status == :stopped_early

          checks = [ redundancy(run) ]
          checks << technologies(eval_case.expect[:technologies], run) if eval_case.expect.key?(:technologies)
          checks << remote(eval_case.expect[:remote], run) if eval_case.expect.key?(:remote)
          checks
        end

        private

        def technologies(expected, run)
          searched = run.tool_calls(:search_jobs).map { |call| call[:arguments][:technology].to_s }
          covered = expected.select { |tech| searched.any? { |term| mentions?(term, tech) } }
          score = (covered.size.to_f / expected.size).round(4)

          return Check.pass(:technologies, "searched #{searched.join(', ')}") if covered.size == expected.size

          Check.fail(:technologies, "missing #{(expected - covered).join(', ')} (searched: #{searched.join(', ')})",
                     score: score)
        end

        def remote(expected, run)
          searches = run.tool_calls(:search_jobs)
          return Check.fail(:remote, "no search was made") if searches.empty?

          wrong = searches.reject { |call| call[:arguments][:remote] == expected }
          return Check.pass(:remote) if wrong.empty?

          Check.fail(:remote, "#{wrong.size}/#{searches.size} searches used remote=#{!expected}",
                     score: 1.0 - (wrong.size.to_f / searches.size).round(4))
        end

        def redundancy(run)
          keys = run.trajectory.map { |call| [ call[:tool], call[:arguments] ] }
          duplicates = keys.size - keys.uniq.size
          return Check.pass(:no_redundant_calls) if duplicates.zero?

          Check.fail(:no_redundant_calls, "#{duplicates} repeated tool call(s)")
        end

        def mentions?(text, technology)
          text.downcase.match?(/\b#{Regexp.escape(technology.to_s.downcase)}\b/)
        end
      end
    end
  end
end

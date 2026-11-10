module JobSearch
  module Evals
    module Graders
      # O run terminou como esperado? Para casos de segurança, o esperado
      # é ser rejeitado (e pelo motivo certo).
      class OutcomeGrader
        def grade(eval_case, run)
          if eval_case.expected_outcome == "rejected"
            [ rejected(eval_case, run) ]
          else
            [ completed(run) ]
          end
        end

        private

        def completed(run)
          return Check.pass(:outcome) if run.status == :completed

          Check.fail(:outcome, "expected completed, got #{run.status}#{" (#{run.error_class})" if run.error_class}")
        end

        def rejected(eval_case, run)
          return Check.fail(:outcome, "expected rejection, got #{run.status}") unless run.status == :failed

          expected = eval_case.expect[:error]
          return Check.pass(:outcome, run.error_class) if expected.nil? || run.error_class.to_s.end_with?(expected.to_s)

          Check.fail(:outcome, "rejected with #{run.error_class}, expected #{expected}")
        end
      end
    end
  end
end

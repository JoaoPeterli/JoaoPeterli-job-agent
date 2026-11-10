module JobSearch
  module Evals
    # Resultado de um caso: passa só se todos os checks passam; a nota é
    # a média das notas dos checks.
    CaseResult = Data.define(:case_id, :tags, :run, :checks) do
      def passed?
        checks.all?(&:passed?)
      end

      def score
        return 0.0 if checks.empty?

        (checks.sum(&:score) / checks.size).round(4)
      end

      def failed_checks
        checks.reject(&:passed?)
      end

      def to_h
        {
          case_id: case_id, tags: tags, passed: passed?, score: score,
          status: run.status.to_s, error_class: run.error_class,
          checks: checks.map(&:to_h),
          metrics: run.metrics.slice("llm_calls", "total_tokens", "cost_usd", "duration_ms")
        }
      end
    end
  end
end

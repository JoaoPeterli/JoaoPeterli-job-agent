module JobSearch
  module Evals
    module Graders
      # O resultado custou o razoável? Lê o "run.metrics" do trace.
      # Custo desconhecido (modelo sem preço) não reprova: vira detalhe.
      class EfficiencyGrader
        def grade(eval_case, run)
          expect = eval_case.expect
          metrics = run.metrics
          checks = []

          checks << limit(:llm_calls, metrics["llm_calls"], expect[:max_llm_calls]) if expect.key?(:max_llm_calls)
          checks << limit(:duration_ms, metrics["duration_ms"], expect[:max_duration_ms]) if expect.key?(:max_duration_ms)
          checks << cost(metrics["cost_usd"], expect[:max_cost_usd]) if expect.key?(:max_cost_usd)
          checks
        end

        private

        def limit(name, value, maximum)
          return Check.fail(name, "no metrics recorded") if value.nil?
          return Check.pass(name, "#{value} <= #{maximum}") if value <= maximum

          Check.fail(name, "#{value} > #{maximum}")
        end

        def cost(value, maximum)
          return Check.pass(:cost_usd, "cost unknown (no pricing configured)") if value.nil?

          limit(:cost_usd, value, maximum)
        end
      end
    end
  end
end

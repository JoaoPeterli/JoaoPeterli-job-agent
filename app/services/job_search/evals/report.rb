require "json"

module JobSearch
  module Evals
    # Relatório agregado de um eval e comparação com uma baseline.
    #
    # A baseline é o to_h de um relatório anterior aprovado (JSON). Uma
    # regressão é: pass rate caiu mais que a tolerância, ou um caso que
    # passava agora falha. Melhorias nunca reprovam.
    class Report
      attr_reader :dataset_name, :target, :results

      def initialize(dataset_name:, target:, results:)
        @dataset_name = dataset_name
        @target = target
        @results = results
      end

      def passed?
        results.all?(&:passed?)
      end

      def pass_rate
        return 0.0 if results.empty?

        (results.count(&:passed?).to_f / results.size).round(4)
      end

      def mean_score
        return 0.0 if results.empty?

        (results.sum(&:score) / results.size).round(4)
      end

      def summary
        {
          dataset: dataset_name, target: target.to_s,
          cases: results.size, passed: results.count(&:passed?),
          pass_rate: pass_rate, mean_score: mean_score,
          checks: check_summary,
          llm_calls: sum_metric("llm_calls"), total_tokens: sum_metric("total_tokens"),
          cost_usd: total_cost, latency_ms: latency
        }
      end

      def to_h
        { summary: summary, cases: results.map(&:to_h) }
      end

      def regressions(baseline, tolerance: 0.0)
        baseline = JSON.parse(JSON.generate(baseline))
        messages = []

        previous_rate = baseline.dig("summary", "pass_rate").to_f
        if pass_rate < previous_rate - tolerance
          messages << "pass rate dropped from #{previous_rate} to #{pass_rate}"
        end

        previously_passing = Array(baseline["cases"]).select { |item| item["passed"] }.map { |item| item["case_id"] }
        results.each do |result|
          next if result.passed? || !previously_passing.include?(result.case_id)

          messages << "case #{result.case_id} regressed: #{result.failed_checks.map(&:name).join(', ')}"
        end

        messages
      end

      def to_text
        lines = [ "Eval #{dataset_name} (#{target}): #{summary[:passed]}/#{results.size} passed, " \
                  "pass rate #{pass_rate}, mean score #{mean_score}" ]

        results.each do |result|
          lines << format("  %-4s %-28s score %.2f", result.passed? ? "ok" : "FAIL", result.case_id, result.score)
          result.failed_checks.each { |check| lines << "         - #{check.name}: #{check.detail}" }
        end

        lines << "  latency p50 #{latency[:p50]}ms p95 #{latency[:p95]}ms | llm calls #{summary[:llm_calls]} | " \
                 "cost #{total_cost.nil? ? 'unknown' : "$#{total_cost}"}"
        lines.join("\n")
      end

      private

      def check_summary
        results.flat_map(&:checks).group_by(&:name).transform_values do |checks|
          passed = checks.count(&:passed?)
          { passed: passed, total: checks.size, pass_rate: (passed.to_f / checks.size).round(4) }
        end
      end

      def sum_metric(name)
        results.sum { |result| result.run.metrics[name].to_i }
      end

      # nil quando algum caso não teve custo conhecido: soma parcial engana.
      def total_cost
        costs = results.map { |result| result.run.metrics["cost_usd"] }
        return nil if costs.empty? || costs.any?(&:nil?)

        costs.sum.round(6)
      end

      def latency
        durations = results.filter_map { |result| result.run.metrics["duration_ms"] }.sort

        { p50: percentile(durations, 50), p95: percentile(durations, 95) }
      end

      # Nearest-rank: valor real observado, sem interpolação.
      def percentile(sorted, rank)
        return nil if sorted.empty?

        sorted[((rank / 100.0) * sorted.size).ceil.clamp(1, sorted.size) - 1]
      end
    end
  end
end

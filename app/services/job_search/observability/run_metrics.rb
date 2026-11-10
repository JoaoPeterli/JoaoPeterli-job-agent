module JobSearch
  module Observability
    # Agrega os spans de um run em um único evento "run.metrics".
    #
    # É um listener do Tracer: recebe cada span ao terminar e, quando o
    # span raiz (sem pai) termina, emite o resumo e zera os contadores.
    # Fica desacoplado do agente, do planner e do executor: tudo o que ele
    # sabe vem dos atributos que os spans já carregam.
    #
    # cost_usd só é informado quando TODAS as chamadas tiveram preço
    # (cost_complete: true); somar só parte delas subestimaria o custo.
    #
    # Thread-safe: spans de agentes em paralelo chegam de várias threads.
    class RunMetrics
      TOKEN_KEYS = %w[input_tokens cached_input_tokens output_tokens total_tokens].freeze

      attr_reader :last_summary

      def initialize(event_logger: EventLogger.new)
        @event_logger = event_logger
        @lock = Mutex.new
        reset
      end

      def call(span)
        @lock.synchronize { record(span.transform_keys(&:to_s)) }
      end

      private

      def record(span)
        case span["name"]
        when "llm.call" then add_llm_call(span)
        when "planning.attempt" then @planning_attempts += 1
        when "step" then add_step(span)
        end

        finish(span) if span["parent_span_id"].nil?
      end

      def reset
        @llm_calls = 0
        @llm_latencies = []
        @tokens = TOKEN_KEYS.to_h { |key| [ key, 0 ] }
        @usage_missing = 0
        @cost_usd = 0.0
        @unpriced_calls = 0
        @planning_attempts = 0
        @tool_calls = 0
        @failed_tool_calls = 0
        @tool_latency_ms = 0.0
      end

      def add_llm_call(span)
        @llm_calls += 1
        @llm_latencies << span["duration_ms"].to_f
        @usage_missing += 1 unless span["usage_reported"]
        TOKEN_KEYS.each { |key| @tokens[key] += span[key].to_i }

        if span["cost_usd"]
          @cost_usd += span["cost_usd"].to_f
        else
          @unpriced_calls += 1
        end
      end

      def add_step(span)
        @tool_calls += 1
        @failed_tool_calls += 1 if span["status"] == "error"
        @tool_latency_ms += span["duration_ms"].to_f
      end

      def finish(root)
        @last_summary = summary(root)
        @event_logger.info(event: "run.metrics", **@last_summary)
      ensure
        reset
      end

      def summary(root)
        {
          trace_id: root["trace_id"],
          run_status: root["run_status"] || root["status"],
          duration_ms: root["duration_ms"],
          planning_attempts: @planning_attempts,
          llm_calls: @llm_calls,
          llm_latency_ms: @llm_latencies.sum.round(2),
          llm_latency_max_ms: (@llm_latencies.max || 0.0).round(2),
          **@tokens.transform_keys(&:to_sym),
          usage_missing_calls: @usage_missing,
          cost_usd: cost_complete? ? @cost_usd.round(6) : nil,
          cost_complete: cost_complete?,
          tool_calls: @tool_calls,
          failed_tool_calls: @failed_tool_calls,
          tool_latency_ms: @tool_latency_ms.round(2)
        }
      end

      def cost_complete?
        @unpriced_calls.zero?
      end
    end
  end
end

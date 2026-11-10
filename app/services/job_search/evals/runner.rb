module JobSearch
  module Evals
    # Roda cada caso do dataset no sistema real (Container), coleta a
    # trajetória, o output e as métricas do trace, e aplica os graders.
    #
    # target: :agent (agente único), :pipeline (Aula 41) ou :supervisor (Aula 42)
    # container_factory: ->(eval_case, event_logger) { Container.new(...) }
    #   - offline (testes): Container com LLM gravado/roteirizado por caso,
    #     determinístico e de graça;
    #   - online (rake job_search:eval): Container com a OpenAI real.
    #
    # Um caso que lança erro não derruba o eval: vira EvalRun :failed e os
    # graders decidem se isso era o esperado (casos de segurança).
    class Runner
      TARGETS = %i[agent pipeline supervisor].freeze

      DEFAULT_GRADERS = [
        Graders::OutcomeGrader.new,
        Graders::ToolUseGrader.new,
        Graders::ResultGrader.new,
        Graders::EfficiencyGrader.new
      ].freeze

      def initialize(target:, container_factory:, graders: DEFAULT_GRADERS, judge: nil)
        raise ArgumentError, "Unknown eval target: #{target}" unless TARGETS.include?(target.to_sym)

        @target = target.to_sym
        @container_factory = container_factory
        @graders = graders
        @judge = judge
      end

      def run(dataset)
        results = dataset.map { |eval_case| run_case(eval_case) }

        Report.new(dataset_name: dataset.name, target: @target, results: results)
      end

      private

      def run_case(eval_case)
        collector = Observability::EventCollector.new
        container = @container_factory.call(eval_case, collector.event_logger)
        run = execute(container, eval_case, collector)

        graders = @judge ? [ *@graders, @judge ] : @graders
        checks = graders.flat_map { |grader| grader.grade(eval_case, run) }

        CaseResult.new(case_id: eval_case.id, tags: eval_case.tags, run: run, checks: checks)
      end

      def execute(container, eval_case, collector)
        run = @target == :agent ? run_agent(container, eval_case) : run_team(container, eval_case)
        run.with(metrics: metrics(collector))
      rescue StandardError => error
        root = error.is_a?(PipelineStageError) && error.cause ? error.cause : error

        EvalRun.new(status: :failed, error_class: root.class.name, metrics: metrics(collector))
      end

      def run_agent(container, eval_case)
        state = container.agent(objective: eval_case.objective).run

        EvalRun.new(status: state.status, trajectory: trajectory(state, "job_search"), output: agent_output(state))
      end

      def run_team(container, eval_case)
        team = @target == :pipeline ? container.pipeline : container.supervisor
        result = team.run(objective: eval_case.objective)

        EvalRun.new(
          status: result.status,
          trajectory: result.agent_states.flat_map { |id, state| trajectory(state, id) },
          output: result.output&.value
        )
      end

      # Resultado final do agente único: a análise, se houve; senão as vagas.
      def agent_output(state)
        state.observations_from_tool(:analyze_jobs).last || state.observations_from_tool(:search_jobs).flatten(1)
      end

      def trajectory(state, agent)
        state.actions.map do |action|
          { agent: agent.to_s, tool: action.tool.to_sym, arguments: plain(action.arguments) }
        end
      end

      def plain(value)
        case value
        when ObservationReference then "$ref:#{value.step_name}"
        when Hash then value.to_h { |key, item| [ key.to_sym, plain(item) ] }
        when Array then value.map { |item| plain(item) }
        else value
        end
      end

      def metrics(collector)
        collector.last("run.metrics")&.except("event", "timestamp") || {}
      end
    end
  end
end

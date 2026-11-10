module JobSearch
  module Evals
    # O que aconteceu ao rodar um caso: tudo o que os graders podem olhar.
    #
    # status: :completed, :stopped_early, :failed ou :rejected
    # error_class: classe do erro (o erro "de verdade", sem wrappers)
    # trajectory: chamadas de ferramenta [{agent:, tool:, arguments:}]
    # output: valor final (ex.: vagas pontuadas)
    # metrics: evento "run.metrics" do trace (tokens, custo, latência)
    EvalRun = Data.define(:status, :error_class, :trajectory, :output, :metrics) do
      def initialize(status:, error_class: nil, trajectory: [], output: nil, metrics: {})
        super
      end

      def tool_calls(tool)
        trajectory.select { |call| call[:tool] == tool.to_sym }
      end
    end
  end
end

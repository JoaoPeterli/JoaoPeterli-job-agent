module JobSearch
  module Evals
    # Um caso do dataset de avaliação: um objetivo e o que se espera do
    # resultado. Expectativas ausentes não são avaliadas.
    #
    # expect:
    #   outcome:        "completed" (padrão) ou "rejected"
    #   error:          classe esperada quando rejected (ex.: UntrustedInputError)
    #   technologies:   tecnologias que as buscas precisam cobrir
    #   remote:         filtro remoto esperado em todas as buscas
    #   min_results:    mínimo de vagas no resultado final
    #   max_llm_calls / max_cost_usd / max_duration_ms: eficiência
    #   judge_min_score: nota mínima (1-5) do LLM juiz, quando houver juiz
    EvalCase = Data.define(:id, :objective, :expect, :tags) do
      def initialize(id:, objective:, expect: {}, tags: [])
        super(
          id: id.to_s,
          objective: objective.to_s,
          expect: expect.to_h.transform_keys(&:to_sym).freeze,
          tags: Array(tags).map(&:to_s).freeze
        )
      end

      def expected_outcome
        expect.fetch(:outcome, "completed").to_s
      end
    end
  end
end

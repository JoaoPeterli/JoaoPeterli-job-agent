module JobSearch
  module Evals
    # Resultado de um critério: passou ou não, uma nota de 0 a 1 (crédito
    # parcial, ex.: cobriu 1 de 2 tecnologias) e um detalhe legível.
    Check = Data.define(:name, :passed, :score, :detail) do
      def self.pass(name, detail = nil, score: 1.0) = new(name: name.to_s, passed: true, score: score, detail: detail)
      def self.fail(name, detail, score: 0.0) = new(name: name.to_s, passed: false, score: score, detail: detail)

      def passed? = passed
    end
  end
end

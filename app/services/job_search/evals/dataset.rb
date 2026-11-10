require "yaml"

module JobSearch
  module Evals
    # Conjunto de casos carregado de YAML (evals/*.yml).
    class Dataset
      include Enumerable

      attr_reader :name, :cases

      def self.load(path)
        data = YAML.safe_load_file(path)
        cases = Array(data.fetch("cases")).map do |item|
          EvalCase.new(
            id: item.fetch("id"), objective: item.fetch("objective"),
            expect: item.fetch("expect", {}), tags: item.fetch("tags", [])
          )
        end

        new(name: data.fetch("name", File.basename(path.to_s, ".yml")), cases: cases)
      end

      def initialize(name:, cases:)
        ids = cases.map(&:id)
        duplicate = ids.find { |id| ids.count(id) > 1 }
        raise ArgumentError, "Duplicated eval case: #{duplicate}" if duplicate

        @name = name
        @cases = cases.freeze
      end

      def each(&)
        cases.each(&)
      end
    end
  end
end

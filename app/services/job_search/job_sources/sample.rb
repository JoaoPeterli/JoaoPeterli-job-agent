module JobSearch
  module JobSources
    # Fonte fixa, sem rede: testes, evals e demos. Gera uma vaga para a
    # tecnologia pedida (o comportamento original da SearchJobsTool).
    class Sample
      NAME = "Exemplo".freeze
      HOMEPAGE = nil

      def initialize(**)
      end

      def search(technology:, remote:)
        [
          JobListing.build(
            title: "Senior #{technology} Developer",
            company: "Example Company",
            url: nil,
            source: NAME,
            remote: remote,
            tags: [ technology ]
          )
        ]
      end
    end
  end
end

module JobSearch
  # JSON Schema (strict) da resposta do supervisor. O enum de agentes vem
  # do time: o modelo nem consegue "inventar" um agente na saída
  # estruturada (e o validador recusa de novo, caso o provedor falhe).
  class DelegationOutputSchema
    def initialize(team:)
      @team = team
    end

    def to_h
      {
        type: "object",
        properties: {
          delegations: {
            type: "array",
            items: {
              type: "object",
              properties: {
                id: { type: "string" },
                agent: { type: "string", enum: @team.map(&:name) },
                task: { type: "string" },
                inputs: { type: "array", items: { type: "string" } }
              },
              required: %w[id agent task inputs],
              additionalProperties: false
            }
          }
        },
        required: [ "delegations" ],
        additionalProperties: false
      }
    end
  end
end

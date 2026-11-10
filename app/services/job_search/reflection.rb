module JobSearch
  # Decisão do Reflector ao fim de uma iteração: terminar ou buscar de novo
  # (com uma orientação para o planner). by: "rule" quando uma regra
  # determinística decidiu sem chamar o LLM.
  Reflection = Data.define(:decision, :reason, :guidance, :by) do
    def self.finish(reason, by: "rule") = new(decision: "finish", reason: reason, guidance: nil, by: by)

    def finish? = decision == "finish"
  end
end

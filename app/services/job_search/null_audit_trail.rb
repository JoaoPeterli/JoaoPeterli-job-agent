module JobSearch
  # Trilha que não grava nada: padrão dos componentes fora do Container
  # (ex.: testes unitários que não usam banco).
  class NullAuditTrail
    def record(run_id:, event:, outcome:, details: {}); end
  end
end

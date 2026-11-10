module JobSearch
  # Padrão seguro: nenhuma ação com efeito colateral é aprovada.
  class DenyAllApprovalGate
    def approved?(tool:, fingerprint:, run_id:)
      false
    end
  end
end

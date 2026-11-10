module JobSearch
  # Aprovações concedidas antes da execução, por ação exata.
  #
  # A aprovação é do par (ferramenta, fingerprint dos argumentos
  # resolvidos), não da ferramenta: aprovar a candidatura à vaga 1 não
  # autoriza o agente a se candidatar à vaga 2.
  class StaticApprovalGate
    def initialize(approvals: [])
      @approvals = approvals.map { |tool, fingerprint| [ tool.to_sym, fingerprint ] }.to_set
    end

    def approved?(tool:, fingerprint:, run_id:)
      @approvals.include?([ tool.to_sym, fingerprint ])
    end
  end
end

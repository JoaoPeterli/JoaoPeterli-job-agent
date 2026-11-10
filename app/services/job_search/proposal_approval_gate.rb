module JobSearch
  # Aprovação humana guardada no banco (JobApplication aprovada). Aprova a
  # apply_job só quando existe uma candidatura aprovada com o fingerprint
  # EXATO da ação (vaga + mensagem): mudar um argumento invalida.
  class ProposalApprovalGate
    def approved?(tool:, fingerprint:, run_id:)
      return false unless tool.to_sym == :apply_job

      JobApplication.where(status: "approved", run_id: run_id)
                    .any? { |application| application.approved_for?(fingerprint) }
    end
  end
end

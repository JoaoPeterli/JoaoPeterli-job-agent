module JobSearch
  # "Destino" da apply_job. Não existe API pública para enviar candidatura
  # aos sites de vagas (LinkedIn, Gupy...): aqui a candidatura vira um
  # registro no rastreador do app (status applied), com a mensagem aprovada
  # e o link para concluir no site. Uma integração real (ex.: a API de
  # candidaturas de um ATS) implementaria esta mesma interface.
  #
  # Idempotente pela chave: repetir a chamada (retry, worker duplicado)
  # devolve a mesma candidatura, sem duplicar o efeito.
  class LocalApplicationsClient
    def create_application(job_id:, candidate_id:, idempotency_key:, fencing_token: nil, message: nil)
      application = JobApplication.find_by!(job_key: job_id)
      external_id = "local-#{Digest::SHA256.hexdigest(idempotency_key.to_s).first(12)}"

      application.with_lock do
        unless application.status == "applied"
          application.update!(status: "applied", applied_at: Time.current, external_id: external_id)
        end
      end

      { id: application.external_id, status: application.status, job_id: job_id, candidate_id: candidate_id }
    end
  end
end

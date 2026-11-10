# Candidatura proposta pelo agente e decidida por um humano.
#
#   proposed --aprovar--> approved --apply_job--> applied
#      |                     \--falhou--> failed
#      \--rejeitar--> rejected
#
# A aprovação é da AÇÃO EXATA: grava o fingerprint dos argumentos da
# apply_job (vaga + mensagem). O ToolAuthorizer só deixa a ferramenta rodar
# com o mesmo fingerprint; mudar a mensagem depois de aprovar invalida.
class JobApplication < ApplicationRecord
  STATUSES = %w[proposed approved applied rejected failed].freeze
  MAX_MESSAGE_LENGTH = 1_500
  CANDIDATE_ID = "me".freeze # app pessoal: um candidato só

  validates :status, inclusion: { in: STATUSES }
  validates :job_key, :title, :run_id, presence: true
  validates :message, presence: true, length: { maximum: MAX_MESSAGE_LENGTH }

  scope :recent, -> { order(created_at: :desc) }
  scope :pending, -> { where(status: "proposed") }

  # Argumentos da apply_job: o que o humano aprova é exatamente isto.
  def apply_arguments
    { job_id: job_key, candidate_id: CANDIDATE_ID, message: message }
  end

  def action_fingerprint
    JobSearch::OperationFingerprint.call(tool: :apply_job, arguments: apply_arguments)
  end

  def approve!(message:, by:)
    with_lock do
      raise ArgumentError, "Esta candidatura já foi decidida." unless status == "proposed"

      self.message = message.to_s.strip
      self.status = "approved"
      self.decided_by = by
      self.decided_at = Time.current
      self.approval_fingerprint = action_fingerprint if valid?
      save!
    end
  end

  def reject!(by:)
    with_lock do
      raise ArgumentError, "Esta candidatura já foi decidida." unless status == "proposed"

      update!(status: "rejected", decided_by: by, decided_at: Time.current)
    end
  end

  def approved_for?(fingerprint)
    status == "approved" && approval_fingerprint.present? &&
      ActiveSupport::SecurityUtils.secure_compare(approval_fingerprint, fingerprint)
  end

  def to_job
    { "title" => title, "company" => company, "location" => location, "source" => source, "url" => url }
  end
end

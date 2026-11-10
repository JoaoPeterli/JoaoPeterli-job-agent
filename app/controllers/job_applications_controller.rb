# Humano no laço: o usuário revisa as candidaturas propostas pelo agente,
# pode editar a mensagem, e aprova (a ação exata) ou rejeita.
class JobApplicationsController < ApplicationController
  FILTERS = { "pending" => %w[proposed], "done" => %w[approved applied], "closed" => %w[rejected failed] }.freeze

  def index
    @filter = FILTERS.key?(params[:status]) ? params[:status] : nil
    scope = JobApplication.recent
    @applications = (@filter ? scope.where(status: FILTERS.fetch(@filter)) : scope).limit(50)
    @counts = JobApplication.group(:status).count
  end

  def approve
    application = JobApplication.find(params[:id])
    application.approve!(message: params.require(:message), by: current_user_name)
    audit(application, "application.approved", fingerprint: application.approval_fingerprint, decided_by: current_user_name)
    JobSearch::ExecuteApplicationJob.perform_later(application.id)
    redirect_back_or_to job_applications_path, notice: "Candidatura aprovada. O agente está registrando agora."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to job_applications_path, alert: e.record.errors.full_messages.to_sentence
  rescue ArgumentError => e
    redirect_back_or_to job_applications_path, alert: e.message
  end

  def reject
    application = JobApplication.find(params[:id])
    application.reject!(by: current_user_name)
    audit(application, "application.rejected", decided_by: current_user_name)
    redirect_back_or_to job_applications_path, notice: "Candidatura rejeitada. O agente não vai propor esta vaga de novo."
  rescue ArgumentError => e
    redirect_back_or_to job_applications_path, alert: e.message
  end

  private

  # A decisão humana entra na cadeia de auditoria do run que propôs.
  def audit(application, event, **details)
    JobSearch::AuditTrail.new.record(run_id: application.run_id, event: event, outcome: "info",
                                     details: { application_id: application.id, **details })
  end
end

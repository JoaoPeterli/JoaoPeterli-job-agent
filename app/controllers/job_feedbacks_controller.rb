# 👍/👎 nas vagas de um run. O navegador manda só o run e a chave da vaga:
# os dados vêm do resultado salvo do run, então não dá para forjar uma
# vaga pelo formulário.
class JobFeedbacksController < ApplicationController
  def create
    run = AgentRun.find(params.require(:run_id))
    verdict = params.require(:verdict)
    raise ActionController::BadRequest, "invalid verdict" unless JobFeedback::VERDICTS.include?(verdict)

    job = Array(run.result["output"]).find { |item| item.is_a?(Hash) && JobFeedback.key_for(item) == params.require(:job_key) }
    return head(:not_found) unless job

    feedback = JobFeedback.toggle!(job, verdict: verdict, run_id: run.id)
    # Embedding da marcação (RAG) fora do clique; trocar 👍↔👎 mantém o vetor.
    JobSearch::EmbedFeedbackJob.perform_later(feedback.id) if feedback && feedback.embedding.nil?
    redirect_to run_path(run, anchor: "vagas")
  end

  # Remover uma marcação pela tela "Meu perfil".
  def destroy
    JobFeedback.find(params[:id]).destroy!
    redirect_to edit_profile_path(anchor: "preferencias"), notice: "Marcação removida."
  end
end

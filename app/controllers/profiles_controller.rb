# "Meu perfil": skills, senioridade e modalidade usadas na nota de
# aderência das vagas. Vale para os próximos runs (os antigos mantêm a nota).
class ProfilesController < ApplicationController
  def edit
    @profile = CandidateProfile.current
    load_feedbacks
  end

  def update
    @profile = CandidateProfile.current
    @profile.assign_attributes(profile_params)

    if @profile.save
      redirect_to edit_profile_path, notice: "Perfil salvo. As próximas buscas já usam este perfil."
    else
      flash.now[:alert] = @profile.errors.full_messages.to_sentence
      load_feedbacks
      render :edit, status: :unprocessable_content
    end
  end

  private

  def load_feedbacks
    @feedbacks = JobFeedback.recent.limit(50)
    @feedback_counts = JobFeedback.group(:verdict).count
  end

  def profile_params
    params.require(:candidate_profile).permit(:skills_text, :seniority, :remote, :location)
  end
end

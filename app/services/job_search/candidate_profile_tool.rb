module JobSearch
  # Perfil do candidato salvo em "Meu perfil" (CandidateProfile) e, quando
  # existe, a memória de preferências: as vagas que ele marcou como "gostei"
  # ou "descartei" (JobFeedback). Sem perfil salvo, usa o padrão.
  class CandidateProfileTool
    def call
      profile = CandidateProfile.current.to_tool_output
      preferences = JobFeedback.preferences

      preferences.values.any?(&:any?) ? profile.merge(preferences: preferences) : profile
    end
  end
end

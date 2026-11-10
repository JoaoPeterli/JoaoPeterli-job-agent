module JobSearch
  # Perfil do candidato salvo em "Meu perfil" (CandidateProfile). Sem
  # perfil salvo, usa o padrão (CandidateProfile::DEFAULTS).
  class CandidateProfileTool
    def call
      CandidateProfile.current.to_tool_output
    end
  end
end

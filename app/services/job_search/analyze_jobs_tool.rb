module JobSearch
  # Nota de aderência (0-100) de cada vaga ao perfil do candidato:
  #
  #   skills       20 por skill do perfil no título ou nas tags (máx. 60)
  #   senioridade  20 se o título pede o nível do perfil; 10 se não cita
  #                nível nenhum; 0 se pede outro nível
  #   modalidade   20 se a vaga é remota e o perfil quer remoto; perfil que
  #                aceita presencial também ganha 20 com vaga na sua cidade
  class AnalyzeJobsTool
    SKILL_POINTS = 20
    MAX_SKILL_POINTS = 60
    SENIORITY_POINTS = 20
    UNSTATED_SENIORITY_POINTS = 10
    WORKPLACE_POINTS = 20

    SENIORITY_PATTERNS = {
      "junior" => /\b(j[uú]nior|jr\.?|entry[- ]level|trainee|est[aá]gi[oá]ri[oa]?)(?![[:alnum:]])/i,
      "pleno" => /\b(pleno|mid[- ]?level|intermediate)\b/i,
      "senior" => /\b(s[eê]nior|sr\.?)(?![[:alnum:]])/i,
      "especialista" => /\b(staff|principal|especialista|specialist|tech lead|lead)\b/i
    }.freeze

    def call(jobs:, profile:)
      profile = normalize(profile)

      jobs.map do |job|
        job.merge(score: skill_points(job, profile) + seniority_points(job, profile) + workplace_points(job, profile))
      end
    end

    private

    def normalize(profile)
      profile = profile.to_h.transform_keys(&:to_sym)
      profile.merge(skills: Array(profile[:skills]), seniority: profile[:seniority].to_s.downcase.tr("ê", "e"))
    end

    def skill_points(job, profile)
      text = ([ job[:title] ] + Array(job[:tags])).compact.join(" | ")
      matches = profile[:skills].count do |skill|
        text.match?(/(?<![[:alnum:]])#{Regexp.escape(skill)}(?![[:alnum:]])/i)
      end

      [ matches * SKILL_POINTS, MAX_SKILL_POINTS ].min
    end

    def seniority_points(job, profile)
      levels = SENIORITY_PATTERNS.select { |_, pattern| job[:title].to_s.match?(pattern) }.keys
      return UNSTATED_SENIORITY_POINTS if levels.empty?

      levels.include?(profile[:seniority]) ? SENIORITY_POINTS : 0
    end

    def workplace_points(job, profile)
      return WORKPLACE_POINTS if job[:remote] && profile[:remote]
      return 0 if profile[:remote]

      near = profile[:location].present? && job[:location].to_s.downcase.include?(profile[:location].to_s.downcase)
      job[:remote] || near ? WORKPLACE_POINTS : 0
    end
  end
end

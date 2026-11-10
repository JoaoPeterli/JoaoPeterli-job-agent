# Perfil profissional do usuário (app pessoal: uma linha só). Alimenta a
# ferramenta candidate_profile e, por ela, a nota de aderência das vagas.
class CandidateProfile < ApplicationRecord
  SENIORITIES = {
    "junior" => "Júnior",
    "pleno" => "Pleno",
    "senior" => "Sênior",
    "especialista" => "Especialista / Staff"
  }.freeze

  # Perfil usado enquanto o usuário não salva o dele (e nos testes).
  DEFAULTS = { skills: %w[Ruby Rails AWS], seniority: "senior", remote: true, location: nil }.freeze

  MAX_SKILLS = 20
  MAX_SKILL_LENGTH = 40

  validates :seniority, inclusion: { in: SENIORITIES.keys }
  validates :location, length: { maximum: 80 }
  validate :skills_within_limits

  before_validation :normalize_skills

  def self.current
    order(:id).first || new(DEFAULTS)
  end

  # Aceita "Ruby, Rails; AWS" vindo do formulário.
  def skills_text=(text)
    self.skills = text.to_s.split(/[,;\n]/)
  end

  def skills_text
    skills.join(", ")
  end

  # Formato da saída da ferramenta candidate_profile.
  def to_tool_output
    { skills: skills, seniority: seniority, remote: remote, location: location.presence }
  end

  private

  def normalize_skills
    self.skills = Array(skills).map { |skill| skill.to_s.squish }.reject(&:empty?).uniq(&:downcase)
    self.location = location.to_s.squish.presence
  end

  def skills_within_limits
    errors.add(:skills, "precisa de pelo menos uma skill") if skills.empty?
    errors.add(:skills, "pode ter no máximo #{MAX_SKILLS} itens") if skills.size > MAX_SKILLS
    return unless skills.any? { |skill| skill.length > MAX_SKILL_LENGTH }

    errors.add(:skills, "cada skill pode ter no máximo #{MAX_SKILL_LENGTH} caracteres")
  end
end

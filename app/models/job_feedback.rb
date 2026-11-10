# O que o usuário achou de uma vaga: "like" (gostei) ou "dislike"
# (descartei). Alimenta a memória de preferências do avaliador (LLM).
class JobFeedback < ApplicationRecord
  VERDICTS = %w[like dislike].freeze
  # Quantas marcações de cada tipo vão para o prompt do avaliador.
  MAX_IN_MEMORY = 10

  validates :verdict, inclusion: { in: VERDICTS }
  validates :job_key, :title, presence: true
  validates :title, :company, :location, :source, length: { maximum: 200 }
  validates :url, length: { maximum: 2_000 }

  before_validation :normalize

  scope :recent, -> { order(updated_at: :desc) }
  scope :liked, -> { where(verdict: "like") }
  scope :disliked, -> { where(verdict: "dislike") }

  def self.key_for(job)
    JobSearch::JobListing.key_for(title: job["title"] || job[:title], company: job["company"] || job[:company])
  end

  # Marca a vaga; marcar de novo com o mesmo veredito desfaz (toggle).
  # Devolve a marcação salva, ou nil quando desfez.
  def self.toggle!(job, verdict:, run_id: nil)
    feedback = find_or_initialize_by(job_key: key_for(job))
    return feedback.destroy! && nil if feedback.persisted? && feedback.verdict == verdict

    feedback.update!(
      verdict: verdict, run_id: run_id,
      title: job["title"], company: job["company"], location: job["location"], source: job["source"],
      url: JobSearch::JobListing.safe_url(job["url"]), remote: job["remote"].to_s == "true",
      tags: Array(job["tags"]).first(8)
    )
    feedback
  end

  # Memória que vai para o avaliador: as marcações mais recentes de cada tipo.
  def self.preferences
    {
      liked: liked.recent.limit(MAX_IN_MEMORY).map(&:to_memory),
      disliked: disliked.recent.limit(MAX_IN_MEMORY).map(&:to_memory)
    }
  end

  def to_memory
    { title: title, company: company, location: location, remote: remote, tags: tags }
  end

  def liked? = verdict == "like"

  private

  def normalize
    %i[title company location source].each { |field| self[field] = self[field].to_s.squish.truncate(200).presence }
    self.tags = Array(tags).map { |tag| tag.to_s.squish.truncate(60) }.reject(&:empty?).uniq
  end
end

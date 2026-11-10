# Toda vaga vista em algum run, com o embedding do texto dela (pgvector).
# Base da busca semântica e das "vagas parecidas". Uma linha por vaga
# (job_key = chave de deduplicação do agregador).
class JobPosting < ApplicationRecord
  has_neighbors :embedding

  validates :job_key, :title, :last_seen_at, presence: true

  scope :embedded, -> { where.not(embedding: nil) }

  def to_job
    { "title" => title, "company" => company, "location" => location, "source" => source, "url" => url,
      "remote" => remote, "tags" => tags, "published_at" => published_at&.iso8601 }
  end
end

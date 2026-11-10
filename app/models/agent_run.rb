# Run durável do harness. Transições de estado:
#
#   queued ──claim──▶ running ──▶ completed | stopped_early | failed | cancelled
#      │                 │
#      └──cancel──▶ cancelled      └──lease vencido──▶ queued (recuperação) ou failed
class AgentRun < ApplicationRecord
  MODES = %w[agent pipeline supervisor].freeze
  STATUSES = %w[queued running completed stopped_early failed cancelled].freeze
  FINAL_STATUSES = %w[completed stopped_early failed cancelled].freeze

  validates :mode, inclusion: { in: MODES }
  validates :status, inclusion: { in: STATUSES }
  validates :objective, :idempotency_key, presence: true

  # Filtros do painel: chave da URL => status.
  FILTERS = {
    "active" => %w[queued running],
    "completed" => %w[completed],
    "failed" => %w[failed stopped_early cancelled]
  }.freeze

  scope :recent, -> { order(created_at: :desc) }
  scope :filtered, ->(filter) { FILTERS.key?(filter) ? where(status: FILTERS.fetch(filter)) : all }

  # Indicadores do painel, calculados no banco (métricas ficam no jsonb).
  def self.dashboard_stats
    finished = where(status: FINAL_STATUSES)

    {
      total: count,
      active: where(status: FILTERS.fetch("active")).count,
      success_rate: success_rate(finished.count, finished.where(status: "completed").count),
      total_tokens: sum(Arel.sql("COALESCE((metrics->>'total_tokens')::bigint, 0)")).to_i,
      avg_duration_ms: finished.average(Arel.sql("(metrics->>'duration_ms')::numeric"))&.to_f
    }
  end

  def self.success_rate(finished, completed)
    finished.zero? ? nil : (completed * 100.0 / finished).round
  end
  private_class_method :success_rate

  def finished?
    FINAL_STATUSES.include?(status)
  end

  def cancel_requested?
    cancel_requested_at.present?
  end
end

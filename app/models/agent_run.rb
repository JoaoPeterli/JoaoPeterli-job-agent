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

  def finished?
    FINAL_STATUSES.include?(status)
  end

  def cancel_requested?
    cancel_requested_at.present?
  end
end

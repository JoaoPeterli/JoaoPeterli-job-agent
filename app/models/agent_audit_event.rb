# Evento da trilha de auditoria. Append-only na aplicação: depois de
# gravado não pode ser alterado nem apagado pelo ActiveRecord. (Escrita
# direta no banco ainda é possível; é isso que a hash chain detecta.)
class AgentAuditEvent < ApplicationRecord
  OUTCOMES = %w[info allowed denied completed failed].freeze

  validates :run_id, :seq, :event, :digest, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Audit events cannot be deleted" }

  def readonly?
    persisted? || super
  end
end

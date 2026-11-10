# Soft delete: o run some da lista mas continua no banco (auditoria,
# memória e idempotência seguem válidas) e pode ser restaurado.
class AddDeletedAtToAgentRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_runs, :deleted_at, :datetime
    add_index :agent_runs, :deleted_at
  end
end

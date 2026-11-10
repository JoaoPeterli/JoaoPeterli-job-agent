
class AddReconciliationControlToJobSearchOperations < ActiveRecord::Migration[8.0]
  def change
    add_column :job_search_operations,
               :reconciliation_token,
               :string

    add_column :job_search_operations,
               :reconciliation_expires_at,
               :datetime

    add_column :job_search_operations,
               :reconciliation_attempts,
               :integer,
               default: 0,
               null: false

    add_column :job_search_operations,
               :next_reconciliation_at,
               :datetime

    add_index :job_search_operations,
              [ :status, :next_reconciliation_at ],
              name: "idx_job_search_reconciliation_due"
  end
end

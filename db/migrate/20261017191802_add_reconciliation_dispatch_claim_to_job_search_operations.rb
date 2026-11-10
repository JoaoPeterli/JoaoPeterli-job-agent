
class AddReconciliationDispatchClaimToJobSearchOperations < ActiveRecord::Migration[8.0]
  def change
    add_column :job_search_operations,
               :reconciliation_dispatch_token,
               :string

    add_column :job_search_operations,
               :reconciliation_dispatch_expires_at,
               :datetime
  end
end

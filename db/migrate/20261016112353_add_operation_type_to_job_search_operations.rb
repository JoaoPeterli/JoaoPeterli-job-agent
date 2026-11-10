
class AddOperationTypeToJobSearchOperations < ActiveRecord::Migration[8.0]
  def change
    add_column :job_search_operations,
               :operation_type,
               :string

    add_index :job_search_operations,
              [ :status, :operation_type ]
  end
end

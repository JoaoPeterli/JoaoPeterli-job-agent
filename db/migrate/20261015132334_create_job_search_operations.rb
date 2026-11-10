class CreateJobSearchOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :job_search_operations do |t|
      t.string :operation_key, null: false
      t.string :status, null: false
      t.string :lease_token
      t.datetime :expires_at
      t.jsonb :result

      t.timestamps
    end

    add_index :job_search_operations,
              :operation_key,
              unique: true
  end
end

class AddFencingTokenToJobSearchOperations < ActiveRecord::Migration[8.0]
  def change
    # Contador monotônico por operação. Cada nova aquisição de lease
    # incrementa o valor, permitindo que recursos externos rejeitem
    # escritas de workers obsoletos (fencing token).
    add_column :job_search_operations,
               :fencing_token,
               :bigint,
               default: 0,
               null: false
  end
end

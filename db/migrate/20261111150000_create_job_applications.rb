# Humano no laço: o agente propõe candidaturas, o usuário aprova (a ação
# exata, pelo fingerprint) ou rejeita, e só então a ferramenta apply_job
# executa. Uma candidatura por vaga (job_key).
class CreateJobApplications < ActiveRecord::Migration[8.0]
  def change
    create_table :job_applications do |t|
      t.uuid :run_id, null: false
      t.string :job_key, null: false
      t.string :title, null: false
      t.string :company
      t.string :location
      t.string :source
      t.string :url
      t.integer :score
      t.string :score_reason
      t.text :message, null: false
      t.string :status, null: false, default: "proposed"
      t.string :approval_fingerprint
      t.string :decided_by
      t.datetime :decided_at
      t.datetime :applied_at
      t.string :external_id
      t.string :error_class
      t.timestamps
    end

    add_index :job_applications, :job_key, unique: true
    add_index :job_applications, %i[status created_at]
    add_index :job_applications, :run_id
  end
end

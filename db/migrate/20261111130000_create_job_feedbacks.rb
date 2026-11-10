# Memória de preferências: o que o usuário achou de cada vaga (gostei ou
# descartei). Uma marcação por vaga (job_key = mesma chave de deduplicação
# do agregador); a mais recente vale.
class CreateJobFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :job_feedbacks do |t|
      t.string :job_key, null: false
      t.string :verdict, null: false
      t.string :title, null: false
      t.string :company
      t.string :location
      t.string :source
      t.string :url
      t.string :tags, array: true, null: false, default: []
      t.boolean :remote, null: false, default: false
      t.uuid :run_id
      t.timestamps
    end

    add_index :job_feedbacks, :job_key, unique: true
    add_index :job_feedbacks, %i[verdict updated_at]
  end
end

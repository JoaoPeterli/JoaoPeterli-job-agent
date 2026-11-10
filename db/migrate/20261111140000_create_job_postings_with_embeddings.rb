# RAG (pgvector): toda vaga vista em um run vira um JobPosting com o
# embedding do texto da vaga; as marcações 👍/👎 também ganham embedding.
# Índices HNSW por distância de cosseno (busca aproximada, rápida).
class CreateJobPostingsWithEmbeddings < ActiveRecord::Migration[8.0]
  DIMENSIONS = 1536 # text-embedding-3-small

  def change
    enable_extension "vector"

    create_table :job_postings do |t|
      t.string :job_key, null: false
      t.string :title, null: false
      t.string :company
      t.string :location
      t.string :source
      t.string :url
      t.string :tags, array: true, null: false, default: []
      t.boolean :remote, null: false, default: false
      t.datetime :published_at
      t.uuid :first_seen_run_id
      t.datetime :last_seen_at, null: false
      t.vector :embedding, limit: DIMENSIONS
      t.timestamps
    end
    add_index :job_postings, :job_key, unique: true
    add_index :job_postings, :embedding, using: :hnsw, opclass: :vector_cosine_ops

    add_column :job_feedbacks, :embedding, :vector, limit: DIMENSIONS
    add_index :job_feedbacks, :embedding, using: :hnsw, opclass: :vector_cosine_ops
  end
end

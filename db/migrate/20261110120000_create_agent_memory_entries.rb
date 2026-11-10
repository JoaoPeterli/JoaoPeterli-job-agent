class CreateAgentMemoryEntries < ActiveRecord::Migration[8.0]
  def change
    # Memória persistente do agente: os eventos da ShortTermMemory de cada
    # execução (run_id), gravados ao fim do run para auditoria, recuperação
    # e para o agente aprender com execuções anteriores.
    create_table :agent_memory_entries do |t|
      t.string :run_id, null: false
      t.text :objective, null: false
      t.integer :seq, null: false
      t.string :kind, null: false
      t.text :content, null: false
      t.datetime :created_at, null: false
    end

    # (run_id, seq) identifica um evento: salvar a mesma memória duas
    # vezes não duplica nada (INSERT ... ON CONFLICT DO NOTHING).
    add_index :agent_memory_entries, [ :run_id, :seq ], unique: true
    add_index :agent_memory_entries, [ :kind, :created_at ]
  end
end

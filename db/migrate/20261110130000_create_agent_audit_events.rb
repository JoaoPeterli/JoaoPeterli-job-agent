class CreateAgentAuditEvents < ActiveRecord::Migration[8.0]
  def change
    # Trilha de auditoria do agente: decisões de segurança (início e fim
    # do run, autorização ou negação de ferramentas), só acrescentadas,
    # nunca alteradas. Cada evento guarda o digest do anterior do mesmo
    # run (hash chain): alterar ou apagar um evento quebra a cadeia.
    create_table :agent_audit_events do |t|
      t.string :run_id, null: false
      t.integer :seq, null: false
      t.string :event, null: false
      t.string :outcome, null: false
      t.jsonb :details, null: false, default: {}
      t.string :prev_digest
      t.string :digest, null: false
      t.datetime :created_at, null: false, precision: 6
    end

    # Um seq por run: duas escritas concorrentes não conseguem "bifurcar"
    # a cadeia; a segunda falha.
    add_index :agent_audit_events, [ :run_id, :seq ], unique: true
    add_index :agent_audit_events, [ :event, :created_at ]
  end
end

class CreateAgentRuns < ActiveRecord::Migration[8.0]
  def change
    # Run durável do harness (Aula 45): o pedido, o estado e o resultado
    # sobrevivem ao processo. O id é o run_id do trace e da auditoria do
    # coordenador.
    create_table :agent_runs, id: :uuid do |t|
      t.string :mode, null: false
      t.text :objective, null: false
      t.string :status, null: false, default: "queued"

      # Mesmo pedido enviado duas vezes (retry do cliente, clique duplo)
      # vira o mesmo run.
      t.string :idempotency_key, null: false

      # Lease: só um worker executa o run por vez. O worker renova
      # locked_until enquanto trabalha; lease vencido = worker morreu.
      t.string :locked_by
      t.datetime :locked_until
      t.integer :attempts, null: false, default: 0

      t.datetime :deadline_at
      t.datetime :cancel_requested_at

      t.jsonb :result, null: false, default: {}
      t.jsonb :metrics, null: false, default: {}
      t.string :error_class

      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :agent_runs, :idempotency_key, unique: true
    add_index :agent_runs, [ :status, :locked_until ]
  end
end

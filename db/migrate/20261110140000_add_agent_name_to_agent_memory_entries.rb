class AddAgentNameToAgentMemoryEntries < ActiveRecord::Migration[8.0]
  def change
    # Com vários agentes, cada papel aprende só com os próprios runs: a
    # lição "Tool not allowed: search_jobs" do analista não serve ao
    # pesquisador. Linhas antigas são do agente único ("job_search").
    add_column :agent_memory_entries, :agent_name, :string, null: false, default: "job_search"
    add_index :agent_memory_entries, [ :agent_name, :kind, :created_at ]
  end
end

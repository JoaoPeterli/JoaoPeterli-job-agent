module JobSearch
  # Persiste a memória de curto prazo de uma execução no PostgreSQL.
  #
  # - save é idempotente: (run_id, seq) é único e a escrita usa
  #   ON CONFLICT DO NOTHING. Salvar de novo (retry, ensure duplo)
  #   só grava os eventos que ainda não existem.
  # - load reconstrói a ShortTermMemory de um run para recuperação.
  # - candidates entrega eventos de outros runs para o MemoryRetriever.
  #
  # agent_name separa a memória de cada papel (multiagente).
  class PersistentMemoryStore
    DEFAULT_AGENT_NAME = "job_search".freeze

    def save(run_id:, objective:, memory:, agent_name: DEFAULT_AGENT_NAME)
      rows = memory.entries.map do |entry|
        {
          run_id: run_id,
          agent_name: agent_name.to_s,
          objective: objective,
          seq: entry.seq,
          kind: entry.kind.to_s,
          content: entry.content,
          created_at: Time.current
        }
      end

      return 0 if rows.empty?

      AgentMemoryEntry.insert_all(rows, unique_by: [ :run_id, :seq ]).length
    end

    def load(run_id, max_entries: ShortTermMemory::DEFAULT_MAX_ENTRIES)
      entries = AgentMemoryEntry
        .where(run_id: run_id)
        .order(:seq)
        .last(max_entries)
        .map do |record|
          ShortTermMemory::Entry.new(
            seq: record.seq,
            kind: record.kind.to_sym,
            content: record.content
          )
        end

      ShortTermMemory.new(max_entries: max_entries, entries: entries)
    end

    def candidates(kinds:, limit:, exclude_run_id: nil, agent_name: DEFAULT_AGENT_NAME)
      scope = AgentMemoryEntry
        .where(agent_name: agent_name.to_s, kind: kinds.map(&:to_s))
        .order(created_at: :desc, id: :desc)
        .limit(limit)

      scope = scope.where.not(run_id: exclude_run_id) if exclude_run_id

      scope.to_a
    end
  end
end

require "digest"
require "json"

module JobSearch
  # Trilha de auditoria persistente e à prova de adulteração (tamper-evident).
  #
  # - Append-only: cada evento ganha o próximo seq do run.
  # - Hash chain: digest = SHA-256(evento canônico + digest anterior).
  #   Alterar, apagar ou reordenar um evento quebra a cadeia, e #verify
  #   aponta o primeiro seq inválido.
  # - Grava na hora (não no fim do run): se o processo cair, o que já foi
  #   decidido está registrado.
  # - Falha fechada: se a gravação falhar, o erro sobe. Quem chama decide;
  #   o ToolAuthorizer não executa uma ação que não conseguiu auditar.
  #
  # details são metadados (ferramenta, fingerprint, classe de erro); chaves
  # que parecem segredos são filtradas antes de gravar e de calcular o hash.
  #
  # Thread-safe: #record é serializado por um Mutex (seq + digest + insert
  # precisam ser atômicos). Entre processos, quem garante é o índice único.
  class AuditTrail
    VerificationResult = Data.define(:valid, :events, :broken_at_seq, :reason) do
      def valid? = valid
    end

    def initialize(clock: -> { Time.current })
      @clock = clock
      @heads = {}
      @lock = Mutex.new
    end

    def record(run_id:, event:, outcome:, details: {})
      @lock.synchronize { append(run_id, event, outcome, details) }
    end

    def events(run_id)
      AgentAuditEvent.where(run_id: run_id.to_s).order(:seq).to_a
    end

    def verify(run_id)
      records = events(run_id)
      prev_digest = nil

      records.each.with_index(1) do |record, expected_seq|
        reason =
          if record.seq != expected_seq then "missing or reordered event"
          elsif record.prev_digest != prev_digest then "broken link to previous event"
          elsif record.digest != self.class.digest_for(record) then "event content was modified"
          end

        return VerificationResult.new(false, records.size, record.seq, reason) if reason

        prev_digest = record.digest
      end

      VerificationResult.new(true, records.size, nil, nil)
    end

    def self.digest_for(attributes)
      fields = %i[run_id seq event outcome details prev_digest].map { |key| value_of(attributes, key) }
      fields << value_of(attributes, :created_at).utc.iso8601(6)

      Digest::SHA256.hexdigest(JSON.generate(fields))
    end

    def self.value_of(attributes, key)
      value = attributes.is_a?(Hash) ? attributes[key] : attributes.public_send(key)
      key == :details ? canonicalize(value) : value
    end

    # Ordena as chaves recursivamente: o jsonb do PostgreSQL reordena as
    # chaves, e o hash precisa ser o mesmo na gravação e na verificação.
    def self.canonicalize(value)
      case value
      when Hash then value.to_h { |key, item| [ key.to_s, canonicalize(item) ] }.sort.to_h
      when Array then value.map { |item| canonicalize(item) }
      when Symbol then value.to_s
      else value
      end
    end

    private

    def append(run_id, event, outcome, details)
      seq, prev_digest = next_link(run_id)
      attributes = {
        run_id: run_id.to_s,
        seq: seq,
        event: event.to_s,
        outcome: outcome.to_s,
        details: canonical(Observability::SensitiveDataFilter.call(details)),
        prev_digest: prev_digest,
        created_at: @clock.call.utc.floor(6)
      }

      record = AgentAuditEvent.create!(**attributes, digest: self.class.digest_for(attributes))
      @heads[run_id.to_s] = [ record.seq, record.digest ]
      record
    rescue ActiveRecord::RecordNotUnique
      # Outro processo gravou este seq: o cache local estava velho.
      @heads.delete(run_id.to_s)
      raise
    end

    def canonical(details)
      self.class.canonicalize(details || {})
    end

    def next_link(run_id)
      seq, digest = @heads[run_id.to_s] || last_link(run_id)

      [ seq + 1, digest ]
    end

    def last_link(run_id)
      last = AgentAuditEvent.where(run_id: run_id.to_s).order(:seq).last

      last ? [ last.seq, last.digest ] : [ 0, nil ]
    end
  end
end

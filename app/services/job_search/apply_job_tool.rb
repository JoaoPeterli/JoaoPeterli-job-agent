module JobSearch
  class ApplyJobTool
    def initialize(client:)
      @client = client
    end

    # Quando executada pelo Executor com idempotência, a ferramenta recebe
    # o Lease da operação:
    #
    # - lease.key vira a chave de idempotência da API externa. É a mesma
    #   chave que o ApplicationsReconciliationChecker consulta, então a
    #   reconciliação encontra a candidatura criada.
    # - lease.fencing_token permite que a API rejeite um worker obsoleto
    #   que acorde depois de outro worker ter assumido a operação.
    #
    # idempotency_key explícito continua aceito para chamadas diretas.
    # message: texto da candidatura aprovado pelo humano (faz parte da ação
    # aprovada: está no fingerprint).
    def call(job_id:, candidate_id:, message: nil, idempotency_key: nil, lease: nil)
      key = lease ? lease.key : idempotency_key

      raise ArgumentError, "idempotency_key is required" if key.to_s.strip.empty?

      request = {
        job_id: job_id,
        candidate_id: candidate_id,
        idempotency_key: key
      }

      request[:fencing_token] = lease.fencing_token if lease
      request[:message] = message if message

      @client.create_application(**request)
    end
  end
end

module JobSearch
  # Simula a API de candidaturas com idempotência por chave e
  # fencing tokens. Thread-safe, para uso em testes de corrida.
  class FakeApplicationsClient
    def initialize
      @mutex = Mutex.new
      @created_applications = []
      @requests = []
      @rejected_requests = []
      @results_by_key = {}
      @payloads_by_key = {}
      @highest_fencing_token_by_key = {}
      @lose_next_response = false
    end

    def created_applications
      @mutex.synchronize { @created_applications.dup }
    end

    def requests
      @mutex.synchronize { @requests.dup }
    end

    def rejected_requests
      @mutex.synchronize { @rejected_requests.dup }
    end

    def lose_next_response!
      @mutex.synchronize { @lose_next_response = true }
    end

    def create_application(
      job_id:,
      candidate_id:,
      idempotency_key:,
      fencing_token: nil
    )
      @mutex.synchronize do
        payload = {
          job_id: job_id,
          candidate_id: candidate_id
        }

        request = {
          **payload,
          idempotency_key: idempotency_key
        }
        request[:fencing_token] = fencing_token if fencing_token

        @requests << request

        check_fencing_token!(idempotency_key, fencing_token, request)

        if @results_by_key.key?(idempotency_key)
          if @payloads_by_key[idempotency_key] != payload
            raise ArgumentError,
                  "Idempotency key reused with different payload"
          end

          return @results_by_key[idempotency_key]
        end

        result = {
          application_id: @created_applications.size + 1,
          status: "submitted"
        }

        @created_applications << payload
        @payloads_by_key[idempotency_key] = payload
        @results_by_key[idempotency_key] = result

        if @lose_next_response
          @lose_next_response = false

          raise Timeout::Error, "Response lost"
        end

        result
      end
    end

    def find_by_idempotency_key(idempotency_key:)
      @mutex.synchronize { @results_by_key[idempotency_key] }
    end

    private

    # Regra do fencing: a API guarda o maior token já visto por chave e
    # recusa qualquer escrita com token menor.
    def check_fencing_token!(key, fencing_token, request)
      return if fencing_token.nil?

      highest = @highest_fencing_token_by_key[key]

      if highest && fencing_token < highest
        @rejected_requests << request

        raise StaleFencingTokenError,
              "Stale fencing token #{fencing_token} for key=#{key} " \
              "(highest seen: #{highest})"
      end

      @highest_fencing_token_by_key[key] = fencing_token
    end
  end
end

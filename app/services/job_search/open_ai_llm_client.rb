module JobSearch
  class OpenAiLlmClient < LlmClient
    SCHEMA_NAME = "job_search_plan".freeze

    def initialize(
      client:,
      model:,
      output_schema:,
      max_output_tokens: nil,
      schema_name: SCHEMA_NAME,
      response_contract: LlmResponseContract.new,
      schema_validator: StrictSchemaValidator.new
    )
      # Falha no boot, não na primeira chamada à API.
      schema_validator.validate!(output_schema)

      @client = client
      @model = model
      @output_schema = output_schema
      @schema_name = schema_name
      @max_output_tokens = max_output_tokens
      @response_contract = response_contract
    end

    def complete(prompt:)
      @response_contract.text!(generate(prompt: prompt))
    end

    def generate(prompt:)
      to_llm_response(
        @client.responses.create(**request_params(prompt))
      )
    rescue OpenAI::Errors::AuthenticationError,
           OpenAI::Errors::PermissionDeniedError => error
      raise LlmProviderError.new(
        "LLM provider rejected the credentials (HTTP #{error.status}). Check OPENAI_API_KEY.",
        transient: false
      )
    rescue OpenAI::Errors::RateLimitError,
           OpenAI::Errors::InternalServerError,
           OpenAI::Errors::APIConnectionError => error
      raise LlmProviderError.new(
        "LLM provider unavailable (#{error.class.name.demodulize}). Try again later.",
        transient: true
      )
    rescue OpenAI::Errors::APIStatusError => error
      raise LlmProviderError.new(
        "LLM provider rejected the request (HTTP #{error.status}).",
        transient: false
      )
    end

    private

    def request_params(prompt)
      params = {
        model: @model,
        input: prompt,
        text: {
          format: {
            type: :json_schema,
            name: @schema_name,
            strict: true,
            schema: @output_schema
          }
        }
      }

      params[:max_output_tokens] = @max_output_tokens if @max_output_tokens

      params
    end

    def to_llm_response(raw)
      LlmResponse.new(
        text: raw.output_text,
        status: raw.status&.to_sym,
        refusal: refusal_from(raw),
        incomplete_reason: raw.incomplete_details&.reason&.to_sym,
        usage: usage_from(raw.usage),
        model: raw.model&.to_s
      )
    end

    def refusal_from(raw)
      contents = Array(raw.output).flat_map do |item|
        item.respond_to?(:content) ? Array(item.content) : []
      end

      contents.find { |content| content.type == :refusal }&.refusal
    end

    def usage_from(usage)
      return nil unless usage

      LlmUsage.new(
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        total_tokens: usage.total_tokens,
        cached_input_tokens: usage.input_tokens_details&.cached_tokens || 0
      )
    end
  end
end

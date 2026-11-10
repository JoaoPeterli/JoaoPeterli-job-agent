module JobSearch
  class OpenAiLlmClient < LlmClient
    SCHEMA_NAME = "job_search_plan".freeze

    def initialize(
      client:,
      model:,
      output_schema:,
      max_output_tokens: nil,
      response_contract: LlmResponseContract.new,
      schema_validator: StrictSchemaValidator.new
    )
      # Falha no boot, não na primeira chamada à API.
      schema_validator.validate!(output_schema)

      @client = client
      @model = model
      @output_schema = output_schema
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
    end

    private

    def request_params(prompt)
      params = {
        model: @model,
        input: prompt,
        text: {
          format: {
            type: :json_schema,
            name: SCHEMA_NAME,
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
        usage: usage_from(raw.usage)
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
        total_tokens: usage.total_tokens
      )
    end
  end
end

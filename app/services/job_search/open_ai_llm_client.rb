module JobSearch
  class OpenAiLlmClient < LlmClient
    def initialize(
      client:,
      model:,
      output_schema:,
      max_output_tokens: nil
    )
      @client = client
      @model = model
      @output_schema = output_schema
      @max_output_tokens = max_output_tokens
    end

    def complete(prompt:)
      response = @client.responses.create(**request_params(prompt))

      response.output_text
    end

    private

    def request_params(prompt)
      params = {
        model: @model,
        input: prompt,
        text: {
          format: {
            type: :json_schema,
            name: "job_search_plan",
            strict: true,
            schema: @output_schema
          }
        }
      }

      params[:max_output_tokens] = @max_output_tokens if @max_output_tokens

      params
    end
  end
end

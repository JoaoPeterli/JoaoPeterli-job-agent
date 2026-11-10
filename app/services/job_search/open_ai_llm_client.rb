module JobSearch
  class OpenAiLlmClient < LlmClient
    def initialize(
      client:,
      model:,
      output_schema:
    )
      @client = client
      @model = model
      @output_schema = output_schema
    end

    def complete(prompt:)
      response = @client.responses.create(
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
      )

      response.output_text
    end
  end
end

module JobSearch
  # Um estágio do pipeline multiagente falhou. O erro original fica em
  # #cause; messages traz a conversa até a falha (para depuração).
  class PipelineStageError < StandardError
    attr_reader :stage, :pipeline_run_id, :messages

    def initialize(message, stage:, pipeline_run_id:, messages:)
      super(message)
      @stage = stage
      @pipeline_run_id = pipeline_run_id
      @messages = messages.freeze
    end
  end
end

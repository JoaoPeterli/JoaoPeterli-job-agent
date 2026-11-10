module JobSearch
  # Depois de um run concluído, o agente propõe candidaturas (humano no laço).
  class ProposeApplicationsJob < ApplicationJob
    queue_as :default
    discard_on ActiveRecord::RecordNotFound

    def perform(run_id)
      ApplicationProposer.new(llm_client: Container.new.application_draft_llm_client).propose(AgentRun.find(run_id))
    end
  end
end

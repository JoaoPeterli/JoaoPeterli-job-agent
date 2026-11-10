module JobSearch
  # Executa a candidatura logo depois da aprovação humana.
  class ExecuteApplicationJob < ApplicationJob
    queue_as :default
    discard_on ActiveRecord::RecordNotFound

    def perform(application_id)
      ApplicationExecutor.new.execute(application_id)
    end
  end
end

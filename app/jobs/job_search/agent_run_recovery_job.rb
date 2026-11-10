module JobSearch
  # Recorrente: devolve para a fila os runs cujo worker morreu (lease
  # vencido). Agendado em config/recurring.yml.
  class AgentRunRecoveryJob < ApplicationJob
    queue_as :default

    def perform
      Harness.new.recover_stale!
    end
  end
end

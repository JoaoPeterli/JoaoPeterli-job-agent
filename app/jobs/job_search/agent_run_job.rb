module JobSearch
  # Executa um AgentRun no worker (Solid Queue em produção).
  #
  # Entrega dupla do job é segura: o Harness faz claim atômico e só um
  # worker executa. Falha transitória -> RunRetryable -> nova tentativa
  # com espera crescente; o Harness limita as tentativas pelo AgentRun.
  class AgentRunJob < ApplicationJob
    queue_as :default

    retry_on JobSearch::RunRetryable, wait: :polynomially_longer, attempts: Harness::MAX_ATTEMPTS

    def perform(run_id)
      Harness.new.execute(run_id)
    end
  end
end

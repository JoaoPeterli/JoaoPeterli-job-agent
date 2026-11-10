# Em produção o AgentRunRecoveryJob roda a cada minuto (config/recurring.yml).
# Em desenvolvimento os jobs rodam dentro do `bin/rails server` (adaptador
# :async): reiniciar o servidor no meio de um run deixava o run preso em
# "Executando". Ao subir o servidor, os runs com lease vencido voltam à fila.
if Rails.env.development? && defined?(Rails::Server)
  Rails.application.config.after_initialize do
    # A segunda passada pega o run cujo lease (60 s) ainda valia no boot.
    [ 5.seconds, (JobSearch::Harness::LEASE_SECONDS + 10).seconds ].each do |wait|
      JobSearch::AgentRunRecoveryJob.set(wait: wait).perform_later
    end
  end
end

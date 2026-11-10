namespace :job_search do
  desc 'Executa o agente para um objetivo. Uso: bin/rails "job_search:run[Encontrar vagas Ruby remotas]"'
  task :run, [ :objective ] => :environment do |_task, args|
    objective = args[:objective].to_s.strip
    abort 'Informe o objetivo: bin/rails "job_search:run[Encontrar vagas Ruby remotas]"' if objective.empty?

    # Spans e o resumo "run.metrics" (tokens, custo, latência) vão para o
    # stderr; o resultado do run continua no stdout.
    logger = Logger.new($stderr, formatter: ->(_severity, _time, _progname, message) { "#{message}\n" })
    event_logger = JobSearch::Observability::EventLogger.new(logger: logger)
    agent = JobSearch::Container.new(event_logger: event_logger).agent(objective: objective)

    begin
      state = agent.run
    rescue JobSearch::LlmBudgetExceeded => error
      abort "Orçamento de LLM do run esgotado: #{error.message}"
    rescue JobSearch::PlanningError => error
      abort "Planejamento falhou: #{error.message}"
    rescue JobSearch::ToolAuthorizationError => error
      abort "Execução bloqueada pela política de ferramentas: #{error.message}"
    end

    puts JSON.pretty_generate(
      run_id: state.run_id,
      report: JobSearch::ExecutionReport.new(state: state).to_h,
      observations: state.observations
    )
  end
end

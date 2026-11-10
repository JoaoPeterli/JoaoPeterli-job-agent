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

namespace :job_search do
  desc 'Mostra e verifica a trilha de auditoria de um run. Uso: bin/rails "job_search:audit[RUN_ID]"'
  task :audit, [ :run_id ] => :environment do |_task, args|
    run_id = args[:run_id].to_s.strip
    abort 'Informe o run_id: bin/rails "job_search:audit[RUN_ID]"' if run_id.empty?

    trail = JobSearch::AuditTrail.new
    events = trail.events(run_id)
    abort "Nenhum evento de auditoria para o run #{run_id}" if events.empty?

    events.each do |event|
      puts format(
        "%<seq>3d  %<at>s  %<event>-20s %<outcome>-9s %<details>s",
        seq: event.seq, at: event.created_at.iso8601(3), event: event.event,
        outcome: event.outcome, details: event.details.to_json
      )
    end

    result = trail.verify(run_id)
    if result.valid?
      puts "\nCadeia íntegra: #{result.events} eventos."
    else
      abort "\nCADEIA VIOLADA no evento #{result.broken_at_seq}: #{result.reason}"
    end
  end
end

namespace :job_search do
  desc 'Executa o time pesquisador -> analista. Uso: bin/rails "job_search:pipeline[Encontrar vagas Ruby remotas]"'
  task :pipeline, [ :objective ] => :environment do |_task, args|
    objective = args[:objective].to_s.strip
    abort 'Informe o objetivo: bin/rails "job_search:pipeline[Encontrar vagas Ruby remotas]"' if objective.empty?

    logger = Logger.new($stderr, formatter: ->(_severity, _time, _progname, message) { "#{message}\n" })
    event_logger = JobSearch::Observability::EventLogger.new(logger: logger)

    begin
      result = JobSearch::Container.new(event_logger: event_logger).pipeline.run(objective: objective)
    rescue JobSearch::PipelineStageError => error
      abort "Estágio #{error.stage} falhou (#{error.cause&.class&.name}). Auditoria: job_search:audit[#{error.pipeline_run_id}]"
    end

    puts JSON.pretty_generate(
      pipeline_run_id: result.run_id,
      status: result.status,
      agent_run_ids: result.agent_run_ids,
      messages: result.messages.map(&:to_h),
      output: result.output.value
    )
  end
end

namespace :job_search do
  desc 'Um supervisor (LLM) delega o objetivo aos especialistas. Uso: bin/rails "job_search:delegate[Vagas Ruby e Rails remotas]"'
  task :delegate, [ :objective ] => :environment do |_task, args|
    objective = args[:objective].to_s.strip
    abort 'Informe o objetivo: bin/rails "job_search:delegate[Vagas Ruby e Rails remotas]"' if objective.empty?

    logger = Logger.new($stderr, formatter: ->(_severity, _time, _progname, message) { "#{message}\n" })
    event_logger = JobSearch::Observability::EventLogger.new(logger: logger)

    begin
      result = JobSearch::Container.new(event_logger: event_logger).supervisor.run(objective: objective)
    rescue JobSearch::PipelineStageError => error
      abort "Delegação #{error.stage} falhou (#{error.cause&.class&.name}). Auditoria: job_search:audit[#{error.pipeline_run_id}]"
    rescue JobSearch::PlanningError => error
      abort "Supervisor não conseguiu delegar: #{error.message}"
    end

    puts JSON.pretty_generate(
      supervisor_run_id: result.run_id,
      status: result.status,
      agent_run_ids: result.agent_run_ids,
      messages: result.messages.map(&:to_h),
      output: result.output&.value
    )
  end
end

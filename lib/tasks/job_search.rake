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

namespace :job_search do
  desc "Avalia a qualidade com o LLM real (gasta tokens). Uso: bin/rails \"job_search:eval[agent]\" " \
       "(agent|pipeline|supervisor; JUDGE=1 liga o LLM juiz; UPDATE_BASELINE=1 grava a baseline)"
  task :eval, [ :target ] => :environment do |_task, args|
    target = (args[:target].presence || "agent").to_sym
    dataset = JobSearch::Evals::Dataset.load(Rails.root.join("evals/job_search.yml"))
    judge = ENV["JUDGE"] == "1" ? JobSearch::Evals::LlmJudge.new(llm_client: JobSearch::Container.new.eval_judge_llm_client) : nil

    report = JobSearch::Evals::Runner.new(
      target: target,
      judge: judge,
      container_factory: ->(_eval_case, event_logger) { JobSearch::Container.new(event_logger: event_logger) }
    ).run(dataset)

    puts report.to_text

    output = Rails.root.join("tmp/evals/#{dataset.name}_#{target}_#{Time.current.strftime('%Y%m%d%H%M%S')}.json")
    FileUtils.mkdir_p(output.dirname)
    File.write(output, JSON.pretty_generate(report.to_h))
    puts "\nRelatório: #{output.relative_path_from(Rails.root)}"

    baseline_path = Rails.root.join("evals/baselines/#{dataset.name}_#{target}.json")

    if ENV["UPDATE_BASELINE"] == "1"
      File.write(baseline_path, JSON.pretty_generate(report.to_h))
      puts "Baseline atualizada: #{baseline_path.relative_path_from(Rails.root)}"
    elsif File.exist?(baseline_path)
      regressions = report.regressions(JSON.parse(File.read(baseline_path)), tolerance: ENV.fetch("TOLERANCE", "0").to_f)
      abort "\nREGRESSÕES:\n- #{regressions.join("\n- ")}" if regressions.any?

      puts "Sem regressões contra a baseline."
    else
      puts "Sem baseline para comparar (rode com UPDATE_BASELINE=1 para criar)."
    end
  end
end

namespace :job_search do
  desc 'Envia um run ao harness (assíncrono). Uso: bin/rails "job_search:submit[Vagas Ruby remotas,agent]" ' \
       "(modo: agent|pipeline|supervisor; KEY=chave de idempotência; INLINE=1 executa neste processo)"
  task :submit, [ :objective, :mode ] => :environment do |_task, args|
    objective = args[:objective].to_s.strip
    abort 'Informe o objetivo: bin/rails "job_search:submit[Vagas Ruby remotas,agent]"' if objective.empty?

    harness = JobSearch::Harness.new
    options = { objective: objective, mode: args[:mode].presence || "agent" }
    options[:idempotency_key] = ENV["KEY"] if ENV["KEY"].present?
    run = harness.submit(**options)
    puts "Run #{run.id} (#{run.status})"

    if ENV["INLINE"] == "1"
      run = harness.execute(run.id) || run.reload
      puts "Status final: #{run.status}#{" (#{run.error_class})" if run.error_class}"
    end
  end

  desc 'Mostra o estado de um run do harness. Uso: bin/rails "job_search:status[RUN_ID]"'
  task :status, [ :run_id ] => :environment do |_task, args|
    run = AgentRun.find(args[:run_id])

    puts JSON.pretty_generate(
      run.slice(:id, :mode, :status, :attempts, :error_class, :started_at, :finished_at, :deadline_at, :cancel_requested_at)
         .merge(metrics: run.metrics, result: run.result)
    )
  end

  desc 'Pede o cancelamento de um run. Uso: bin/rails "job_search:cancel[RUN_ID]"'
  task :cancel, [ :run_id ] => :environment do |_task, args|
    run = JobSearch::Harness.new.cancel(args[:run_id])
    puts "Run #{run.id}: #{run.status}#{' (cancelamento pedido; para no próximo checkpoint)' if run.status == 'running'}"
  end
end

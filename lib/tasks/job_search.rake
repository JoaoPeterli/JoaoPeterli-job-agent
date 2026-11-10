namespace :job_search do
  desc 'Executa o agente para um objetivo. Uso: bin/rails "job_search:run[Encontrar vagas Ruby remotas]"'
  task :run, [ :objective ] => :environment do |_task, args|
    objective = args[:objective].to_s.strip
    abort 'Informe o objetivo: bin/rails "job_search:run[Encontrar vagas Ruby remotas]"' if objective.empty?

    agent = JobSearch::Container.new.agent(objective: objective)

    begin
      state = agent.run
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

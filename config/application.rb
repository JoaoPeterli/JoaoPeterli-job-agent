require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module JobAgent
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Horários exibidos na interface. O banco continua em UTC.
    config.time_zone = "America/Sao_Paulo"

    # Fontes de vagas da ferramenta search_jobs (JobSearch::JobSources).
    # Ex.: JOB_SOURCES=remote_ok,github_br. O JSearch (LinkedIn, Indeed...)
    # e o Jooble entram sozinhos no padrão quando a chave de cada um existe.
    # Empresas acompanhadas via Greenhouse/Lever/Ashby: config/job_companies.yml.
    default_job_sources = %w[remote_ok arbeitnow we_work_remotely github_br greenhouse lever ashby jobicy himalayas]
    default_job_sources << "jsearch" if ENV["JSEARCH_API_KEY"].present?
    default_job_sources << "jooble" if ENV["JOOBLE_API_KEY"].present?
    config.x.job_sources = ENV.fetch("JOB_SOURCES", default_job_sources.join(","))
                              .split(",").map(&:strip).reject(&:empty?)
    # Nota das vagas pelo LLM (JobSearch::JobEvaluator), com motivo. Com
    # "false", fica só a régua fixa da AnalyzeJobsTool (sem custo de LLM).
    config.x.llm_job_evaluation = ENV.fetch("LLM_JOB_EVALUATION", "true") == "true"

    # config.eager_load_paths << Rails.root.join("extras")

    # Aplicação web (Hotwire) + jobs. Era api_only até o front ser criado.
    config.api_only = false
  end
end

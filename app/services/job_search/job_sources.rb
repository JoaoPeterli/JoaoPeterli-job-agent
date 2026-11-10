module JobSearch
  # Fontes de vagas disponíveis. Quais ficam ligadas vem de
  # config.x.job_sources (variável JOB_SOURCES); nos testes, só "sample".
  module JobSources
    REGISTRY = {
      "remote_ok" => "JobSearch::JobSources::RemoteOk",
      "arbeitnow" => "JobSearch::JobSources::Arbeitnow",
      "we_work_remotely" => "JobSearch::JobSources::WeWorkRemotely",
      "github_br" => "JobSearch::JobSources::GithubIssues",
      "sample" => "JobSearch::JobSources::Sample"
    }.freeze

    def self.build(names, fetcher: HttpFetcher.new)
      raise ArgumentError, "No job sources configured (JOB_SOURCES)" if Array(names).empty?

      Array(names).map do |name|
        class_name = REGISTRY.fetch(name.to_s) { raise ArgumentError, "Unknown job source: #{name}" }
        class_name.constantize.new(fetcher: fetcher)
      end
    end

    def self.configured
      build(Rails.configuration.x.job_sources)
    end

    # Fontes reais ligadas, para dar crédito na interface.
    def self.attributions(names = Rails.configuration.x.job_sources)
      Array(names).filter_map do |name|
        klass = REGISTRY[name.to_s]&.constantize
        { name: klass::NAME, url: klass::HOMEPAGE } if klass&.const_get(:HOMEPAGE)
      end
    end
  end
end

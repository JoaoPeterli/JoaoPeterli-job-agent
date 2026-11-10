require "yaml"
require Rails.root.join("spec/support/job_search/routing_llm_client")

module JobSearch
  # Respostas de LLM gravadas por caso de eval (spec/fixtures/evals/<target>/<case>.yml).
  # Permitem rodar o dataset inteiro offline: determinístico e sem custo.
  module EvalCassettes
    module_function

    def client_for(target, case_id, overrides: {})
      routes = overrides.fetch(case_id) { load(target, case_id) }

      RoutingLlmClient.new(routes.transform_values { |responses| responses.map { |item| serialize(item) } })
    end

    def load(target, case_id)
      path = Rails.root.join("spec/fixtures/evals", target.to_s, "#{case_id}.yml")
      YAML.safe_load_file(path).fetch("routes") || {}
    end

    def serialize(item)
      item.is_a?(String) ? item : JSON.generate(item)
    end

    def container_factory(target, overrides: {})
      lambda do |eval_case, event_logger|
        Container.new(llm_client: client_for(target, eval_case.id, overrides: overrides), event_logger: event_logger)
      end
    end
  end
end

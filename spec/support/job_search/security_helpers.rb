require Rails.root.join("spec/support/job_search/scripted_llm_client")
require Rails.root.join("spec/support/job_search/captured_events")

module JobSearch
  # Monta o agente real (Container) com LLM roteirizado, logs capturados
  # e a trilha de auditoria real, para os testes de segurança.
  module SecurityHelpers
    def security_events
      @security_events ||= CapturedEvents.new
    end

    def build_secured_agent(objective, responses)
      llm_client = ScriptedLlmClient.new(responses)
      container = Container.new(llm_client: llm_client, event_logger: security_events.event_logger)

      [ container.agent(objective: objective), llm_client, container.audit_trail ]
    end

    def plan_json(*steps)
      JSON.generate(steps: steps.map { |name, tool, arguments, dependencies|
        { name: name, tool: tool, arguments: arguments || {}, dependencies: dependencies || [] }
      })
    end

    def audit_summary(audit_trail, run_id)
      audit_trail.events(run_id).map { |event| [ event.event, event.outcome ] }
    end

    def last_run_id
      AgentAuditEvent.order(:id).last&.run_id
    end
  end
end

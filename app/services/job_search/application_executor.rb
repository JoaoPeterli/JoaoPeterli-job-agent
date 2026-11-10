module JobSearch
  # Executa uma candidatura APROVADA por um humano. Monta um plano de um
  # passo (apply_job com os argumentos aprovados) e roda pelo mesmo caminho
  # de qualquer ferramenta: ToolAuthorizer (papel APPLIER + aprovação da ação
  # exata, ProposalApprovalGate), idempotência com lease, auditoria na trilha
  # do run de origem. Uma falha (inclusive aprovação inválida) vira "failed".
  class ApplicationExecutor
    def initialize(container: Container.new, audit_trail: AuditTrail.new)
      @container = container
      @audit_trail = audit_trail
    end

    def execute(application_id)
      application = JobApplication.find(application_id)
      return application unless application.status == "approved"

      @container.plan_executor(
        audit_trail: @audit_trail, profile: AgentProfiles::APPLIER, approval_gate: ProposalApprovalGate.new
      ).execute(plan: plan_for(application), state: AgentState.new(objective: "apply: #{application.title}", run_id: application.run_id))

      application.reload.tap { |applied| audit(applied, "application.applied", "completed") }
    rescue StandardError => error
      raise if application.nil?

      application.update!(status: "failed", error_class: error.class.name)
      audit(application, "application.failed", "failed", error_class: error.class.name)
      application
    end

    private

    def plan_for(application)
      Plan.new(steps: [
        Step.new(name: :apply, action: AgentAction.new(tool: :apply_job, arguments: application.apply_arguments))
      ])
    end

    def audit(application, event, outcome, **details)
      @audit_trail.record(run_id: application.run_id, event: event, outcome: outcome,
                          details: { application_id: application.id, **details })
    end
  end
end

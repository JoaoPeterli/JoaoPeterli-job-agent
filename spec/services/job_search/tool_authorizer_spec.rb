require "rails_helper"

RSpec.describe JobSearch::ToolAuthorizer do
  let(:tool_catalog) do
    JobSearch::ToolCatalog.new(
      definitions: [
        JobSearch::ToolDefinition.new(name: :search_jobs, description: "Search", side_effects: false),
        JobSearch::ToolDefinition.new(name: :candidate_profile, description: "Profile", side_effects: false),
        JobSearch::ToolDefinition.new(name: :apply_job, description: "Apply", side_effects: true)
      ]
    )
  end

  def action(tool, **arguments)
    JobSearch::AgentAction.new(tool: tool, arguments: arguments)
  end

  def step(name, tool, **arguments)
    JobSearch::Step.new(name: name, action: action(tool, **arguments), dependencies: [])
  end

  def fingerprint(tool, **arguments)
    JobSearch::OperationFingerprint.call(tool: tool, arguments: arguments)
  end

  describe "#authorize!" do
    it "allows read-only tools in the allowlist" do
      authorizer = described_class.new(tool_catalog: tool_catalog, allowed_tools: [ :search_jobs ])

      expect(authorizer.authorize!(action(:search_jobs, technology: "Ruby"), run_id: "run-1")).to be(true)
    end

    it "rejects tools outside the allowlist" do
      authorizer = described_class.new(tool_catalog: tool_catalog, allowed_tools: [ :search_jobs ])

      expect { authorizer.authorize!(action(:candidate_profile), run_id: "run-1") }
        .to raise_error(JobSearch::ToolNotAuthorizedError, "Tool not authorized: candidate_profile")
    end

    it "allows every catalog tool when no allowlist is given" do
      authorizer = described_class.new(tool_catalog: tool_catalog)

      expect(authorizer.permitted?(:candidate_profile)).to be(true)
    end

    it "enforces the per-tool limit within a run" do
      authorizer = described_class.new(tool_catalog: tool_catalog, max_calls_per_tool: { search_jobs: 2 })

      2.times { authorizer.authorize!(action(:search_jobs), run_id: "run-1") }

      expect { authorizer.authorize!(action(:search_jobs), run_id: "run-1") }
        .to raise_error(JobSearch::ToolCallLimitExceeded, "Tool search_jobs exceeded 2 calls in this run")
    end

    it "resets the limit on start!" do
      authorizer = described_class.new(tool_catalog: tool_catalog, max_calls_per_tool: { search_jobs: 1 })
      authorizer.authorize!(action(:search_jobs), run_id: "run-1")

      authorizer.start!

      expect(authorizer.authorize!(action(:search_jobs), run_id: "run-2")).to be(true)
    end

    it "denies side-effect tools by default" do
      authorizer = described_class.new(tool_catalog: tool_catalog)

      expect { authorizer.authorize!(action(:apply_job, job_id: 1), run_id: "run-1") }
        .to raise_error(JobSearch::ApprovalRequiredError) { |error|
          expect(error).to be_a(JobSearch::PermanentError)
          expect(error.tool).to eq(:apply_job)
          expect(error.fingerprint).to eq(fingerprint(:apply_job, job_id: 1))
        }
    end

    it "allows a side-effect action approved for those exact arguments" do
      gate = JobSearch::StaticApprovalGate.new(approvals: [ [ :apply_job, fingerprint(:apply_job, job_id: 1) ] ])
      authorizer = described_class.new(tool_catalog: tool_catalog, approval_gate: gate)

      expect(authorizer.authorize!(action(:apply_job, job_id: 1), run_id: "run-1")).to be(true)
      expect { authorizer.authorize!(action(:apply_job, job_id: 2), run_id: "run-1") }
        .to raise_error(JobSearch::ApprovalRequiredError)
    end

    it "does not count a denied call against the limit" do
      gate = JobSearch::StaticApprovalGate.new(approvals: [ [ :apply_job, fingerprint(:apply_job, job_id: 2) ] ])
      authorizer = described_class.new(
        tool_catalog: tool_catalog, approval_gate: gate, max_calls_per_tool: { apply_job: 1 }
      )

      expect { authorizer.authorize!(action(:apply_job, job_id: 1), run_id: "run-1") }
        .to raise_error(JobSearch::ApprovalRequiredError)

      expect(authorizer.authorize!(action(:apply_job, job_id: 2), run_id: "run-1")).to be(true)
    end
  end

  describe "#authorize_plan!" do
    it "rejects a plan that uses a tool outside the allowlist" do
      authorizer = described_class.new(tool_catalog: tool_catalog, allowed_tools: [ :search_jobs ])
      plan = JobSearch::Plan.new(steps: [ step(:search, :search_jobs), step(:apply, :apply_job) ])

      expect { authorizer.authorize_plan!(plan) }
        .to raise_error(JobSearch::ToolNotAuthorizedError, "Tool not authorized: apply_job")
    end

    it "rejects a plan that exceeds a per-tool limit" do
      authorizer = described_class.new(tool_catalog: tool_catalog, max_calls_per_tool: { search_jobs: 1 })
      plan = JobSearch::Plan.new(steps: [ step(:a, :search_jobs, technology: "Ruby"), step(:b, :search_jobs, technology: "Go") ])

      expect { authorizer.authorize_plan!(plan) }
        .to raise_error(JobSearch::ToolCallLimitExceeded, "Plan uses search_jobs 2 times (limit: 1)")
    end
  end
end

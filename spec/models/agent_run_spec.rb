require "rails_helper"

RSpec.describe AgentRun do
  def create_run(**attributes)
    described_class.create!({ mode: "agent", objective: "Vagas Ruby", idempotency_key: SecureRandom.uuid }.merge(attributes))
  end

  describe ".dashboard_stats" do
    it "summarizes counts, success rate, tokens and average duration in the database" do
      create_run(status: "completed", metrics: { "total_tokens" => 1000, "duration_ms" => 1000 })
      create_run(status: "completed", metrics: { "total_tokens" => 500, "duration_ms" => 3000 })
      create_run(status: "failed", metrics: { "duration_ms" => 2000 })
      create_run(status: "cancelled")
      create_run(status: "running", metrics: { "total_tokens" => 10 })

      expect(described_class.dashboard_stats).to eq(
        total: 5, active: 1, success_rate: 50, total_tokens: 1510, avg_duration_ms: 2000.0
      )
    end

    it "has no success rate or duration before any run finishes" do
      create_run(status: "queued")

      expect(described_class.dashboard_stats).to include(success_rate: nil, avg_duration_ms: nil, total_tokens: 0)
    end
  end

  describe ".filtered" do
    it "groups statuses by filter and returns everything for an unknown filter" do
      %w[queued running completed stopped_early failed cancelled].each { |status| create_run(status: status) }

      expect(described_class.filtered("active").pluck(:status)).to match_array(%w[queued running])
      expect(described_class.filtered("failed").pluck(:status)).to match_array(%w[stopped_early failed cancelled])
      expect(described_class.filtered("nope").count).to eq(6)
    end
  end
end

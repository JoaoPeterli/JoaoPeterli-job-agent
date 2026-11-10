
require "rails_helper"

RSpec.describe JobSearch::Observability::EventLogger do
  let(:logger) do
    instance_double(Logger).tap do |instance|
      allow(instance).to receive(:info)
      allow(instance).to receive(:warn)
      allow(instance).to receive(:error)
    end
  end

  subject(:event_logger) do
    described_class.new(logger: logger)
  end

  describe "#info" do
    it "writes a structured JSON event" do
      event_logger.info(
        event: "reconciliation.started",
        operation_key: "application-123",
        operation_type: "apply_job",
        attempt: 1
      )

      expect(logger).to have_received(:info) do |message|
        data = JSON.parse(message)

        expect(data["event"]).to eq("reconciliation.started")
        expect(data["operation_key"]).to eq("application-123")
        expect(data["operation_type"]).to eq("apply_job")
        expect(data["attempt"]).to eq(1)
      end
    end
  end

  describe "structured logging" do
    it "writes warning events" do
      event_logger.warn(
        event: "reconciliation.retry",
        operation_key: "application-123",
        attempt: 2
      )

      expect(logger).to have_received(:warn) do |message|
        data = JSON.parse(message)

        expect(data["event"]).to eq("reconciliation.retry")
        expect(data["attempt"]).to eq(2)
      end
    end

    it "writes error events" do
      event_logger.error(
        event: "reconciliation.failed",
        error_class: "Timeout::Error"
      )

      expect(logger).to have_received(:error) do |message|
        data = JSON.parse(message)

        expect(data["event"]).to eq("reconciliation.failed")
        expect(data["error_class"]).to eq("Timeout::Error")
      end
    end

    it "includes a valid ISO 8601 timestamp" do
      event_logger.info(event: "agent.started")

      expect(logger).to have_received(:info) do |message|
        data = JSON.parse(message)

        expect(
          Time.iso8601(data.fetch("timestamp"))
        ).to be_a(Time)
      end
    end

    it "filters sensitive attributes" do
      event_logger.info(
        event: "application.submitted",
        operation_key: "application-123",
        access_token: "secret-123",
        password: "password-456",
        api_key: "api-key-789"
      )

      expect(logger).to have_received(:info) do |message|
        data = JSON.parse(message)

        expect(data["operation_key"]).to eq("application-123")
        expect(data["access_token"]).to eq("[FILTERED]")
        expect(data["password"]).to eq("[FILTERED]")
        expect(data["api_key"]).to eq("[FILTERED]")
      end
    end

    it "filters nested credentials without mutating original data" do
      attributes = {
        candidate: {
          email: "candidate@example.com",
          credentials: {
            access_token: "private-token"
          }
        },
        integrations: [
          {
            provider: "external-api",
            api_key: "private-api-key"
          }
        ]
      }

      original = Marshal.load(Marshal.dump(attributes))

      event_logger.info(
        event: "agent.started",
        **attributes
      )

      expect(logger).to have_received(:info) do |message|
        data = JSON.parse(message)

        expect(
          data.dig("candidate", "credentials", "access_token")
        ).to eq("[FILTERED]")

        expect(
          data.dig("integrations", 0, "api_key")
        ).to eq("[FILTERED]")

        expect(
          data.dig("candidate", "email")
        ).to eq("candidate@example.com")
      end

      expect(attributes).to eq(original)
    end
  end
end

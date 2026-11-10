
require "rails_helper"

RSpec.describe JobSearch::IdempotencyPolicy do
  describe "timeout handling with PostgreSQL" do
    let(:store) do
      JobSearch::PostgresIdempotencyStore.new(
        ttl_seconds: 30
      )
    end

    let(:policy) do
      described_class.new(store: store)
    end

    let(:key) { "timeout-application-123" }

    it "marks an operation uncertain after a timeout" do
      expect do
        policy.call(key: key) do
          raise JobSearch::ToolTimeoutError,
                "External API timeout"
        end
      end.to raise_error(JobSearch::ToolTimeoutError)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("uncertain")
      expect(store.acquire(key)).to be_nil
    end

    it "prevents retrying an uncertain operation" do
      begin
        policy.call(key: key) do
          raise JobSearch::ToolTimeoutError,
                "External API timeout"
        end
      rescue JobSearch::ToolTimeoutError
        # Timeout esperado neste teste.
      end

      executions = 0

      expect do
        policy.call(key: key) do
          executions += 1
        end
      end.to raise_error(
        JobSearch::IdempotencyPolicy::OperationInProgress
      )

      expect(executions).to eq(0)
    end
  end
end

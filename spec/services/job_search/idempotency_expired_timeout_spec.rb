
require "rails_helper"

RSpec.describe "Expired lease during external timeout" do
  let(:store) do
    JobSearch::PostgresIdempotencyStore.new(
      ttl_seconds: 30
    )
  end

  let(:policy) do
    JobSearch::IdempotencyPolicy.new(store: store)
  end

  let(:key) { "expired-timeout-application-123" }

  it "exposes the risk of an expired lease after a timeout" do
    expect do
      policy.call(key: key) do
        JobSearchOperation
          .where(operation_key: key)
          .update_all(expires_at: 1.second.ago)

        raise JobSearch::ToolTimeoutError,
              "External API timeout"
      end
    end.to raise_error(JobSearch::ToolTimeoutError)

    operation = JobSearchOperation.find_by!(
      operation_key: key
    )

    # O lease expirou antes de mark_uncertain.
    # A implementação atual não consegue marcar a operação.
    expect(operation.status).to eq("leased")

    # Isso demonstra a possibilidade de uma nova aquisição.
    expect(store.acquire(key)).not_to be_nil
  end
end

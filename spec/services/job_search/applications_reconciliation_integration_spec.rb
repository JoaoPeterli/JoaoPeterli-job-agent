
require "rails_helper"
require Rails.root.join(
  "spec/support/job_search/fake_applications_client"
)

RSpec.describe "Applications reconciliation integration" do
  let(:client) do
    JobSearch::FakeApplicationsClient.new
  end

  let(:store) do
    JobSearch::PostgresIdempotencyStore.new(
      ttl_seconds: 30
    )
  end

  let(:checker) do
    JobSearch::ApplicationsReconciliationChecker.new(
      client: client
    )
  end

  let(:service) do
    JobSearch::ReconciliationService.new(
      store: store,
      checker: checker
    )
  end

  let(:lease) do
    JobSearch::ReconciliationLease.new(
      ttl_seconds: 30
    )
  end

  let(:key) do
    "apply-job-reconcile-#{SecureRandom.uuid}"
  end

  def acquire_reconciliation_token
    reconciliation_token = lease.acquire(key)

    expect(reconciliation_token).to be_present

    reconciliation_token
  end

  it "reconciles a confirmed external application" do
    token = store.acquire(key)

    expect(token).not_to be_nil

    client.lose_next_response!

    expect do
      client.create_application(
        job_id: 123,
        candidate_id: 456,
        idempotency_key: key
      )
    end.to raise_error(Timeout::Error)

    expect(store.mark_uncertain(key, token)).to be(true)
    expect(store.completed?(key)).to be(false)

    reconciliation_token = acquire_reconciliation_token

    result = service.call(
      key: key,
      reconciliation_token: reconciliation_token
    )

    expect(result).to eq(
      application_id: 1,
      status: "submitted"
    )

    expect(store.completed?(key)).to be(true)

    expect(store.completed_result(key)).to eq(
      "application_id" => 1,
      "status" => "submitted"
    )

    expect(client.created_applications.size).to eq(1)
  end

  it "keeps an uncertain operation when no external result exists" do
    token = store.acquire(key)

    expect(token).not_to be_nil
    expect(store.mark_uncertain(key, token)).to be(true)

    reconciliation_token = acquire_reconciliation_token

    result = service.call(
      key: key,
      reconciliation_token: reconciliation_token
    )

    expect(result).to be_nil
    expect(store.completed?(key)).to be(false)

    operation = JobSearchOperation.find_by!(
      operation_key: key
    )

    expect(operation.status).to eq("uncertain")
    expect(operation.next_reconciliation_at).to be > Time.current
  end

  it "keeps the operation uncertain when reconciliation times out" do
    token = store.acquire(key)

    expect(token).not_to be_nil
    expect(store.mark_uncertain(key, token)).to be(true)

    reconciliation_token = acquire_reconciliation_token

    allow(checker)
      .to receive(:call)
      .with(key: key)
      .and_raise(
        Timeout::Error,
        "External API unavailable"
      )

    result = service.call(
      key: key,
      reconciliation_token: reconciliation_token
    )

    expect(result).to be_nil
    expect(store.completed?(key)).to be(false)

    operation = JobSearchOperation.find_by!(
      operation_key: key
    )

    expect(operation.status).to eq("uncertain")
  end
end

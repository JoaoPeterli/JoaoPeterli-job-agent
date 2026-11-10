
require "rails_helper"

RSpec.describe JobSearch::ReconciliationService do
  let(:store) do
    JobSearch::PostgresIdempotencyStore.new
  end

  let(:lease) do
    JobSearch::ReconciliationLease.new(ttl_seconds: 30)
  end

  def create_operation(key)
    JobSearchOperation.create!(
      operation_key: key,
      status: "uncertain",
      operation_type: "apply_job"
    )
  end

  def build_service(checker:, scheduler: nil)
    options = {
      store: store,
      checker: checker
    }

    options[:scheduler] = scheduler if scheduler

    described_class.new(**options)
  end

  describe "#call" do
    it "reconciles an uncertain operation when external success is confirmed" do
      key = "application-#{SecureRandom.uuid}"

      create_operation(key)

      token = lease.acquire(key)

      external_result = {
        application_id: 789,
        status: "submitted"
      }

      checker = double("ExternalStatusChecker")

      expect(checker)
        .to receive(:call)
        .with(key: key)
        .and_return(
          status: :confirmed,
          result: external_result
        )

      service = build_service(checker: checker)

      result = service.call(
        key: key,
        reconciliation_token: token
      )

      expect(result).to eq(external_result)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("completed")

      expect(operation.result).to eq(
        "application_id" => 789,
        "status" => "submitted"
      )
    end
  end

  describe "unconfirmed external outcomes" do
    let(:key) { "application-#{SecureRandom.uuid}" }

    let(:reconciliation_token) do
      lease.acquire(key)
    end

    before do
      create_operation(key)
    end

    it "keeps the operation uncertain when status is unknown" do
      checker = double("ExternalStatusChecker")

      allow(checker)
        .to receive(:call)
        .with(key: key)
        .and_return(status: :unknown)

      service = build_service(checker: checker)

      result = service.call(
        key: key,
        reconciliation_token: reconciliation_token
      )

      expect(result).to be_nil

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("uncertain")
      expect(operation.next_reconciliation_at).to be_present
      expect(store.completed?(key)).to be(false)
    end

    it "does not release the operation when it is not found" do
      checker = double("ExternalStatusChecker")

      allow(checker)
        .to receive(:call)
        .with(key: key)
        .and_return(status: :not_found)

      service = build_service(checker: checker)

      result = service.call(
        key: key,
        reconciliation_token: reconciliation_token
      )

      expect(result).to be_nil

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("uncertain")
      expect(operation.next_reconciliation_at).to be_present
      expect(store.completed?(key)).to be(false)
    end

    it "preserves the uncertain state and schedules a retry when the checker fails" do
      checker = double("ExternalStatusChecker")

      allow(checker)
        .to receive(:call)
        .with(key: key)
        .and_raise(
          IOError,
          "External API unavailable"
        )

      service = build_service(checker: checker)

      expect do
        service.call(
          key: key,
          reconciliation_token: reconciliation_token
        )
      end.to raise_error(
        IOError,
        "External API unavailable"
      )

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("uncertain")
      # A falha conta como tentativa e aplica backoff.
      expect(operation.next_reconciliation_at).to be > Time.current
      expect(store.completed?(key)).to be(false)
    end

    it "rejects unsupported reconciliation statuses" do
      checker = double("ExternalStatusChecker")

      allow(checker)
        .to receive(:call)
        .with(key: key)
        .and_return(status: :invalid)

      service = build_service(checker: checker)

      expect do
        service.call(
          key: key,
          reconciliation_token: reconciliation_token
        )
      end.to raise_error(
        ArgumentError,
        /Unsupported reconciliation status/
      )

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("uncertain")
      # A falha conta como tentativa e aplica backoff.
      expect(operation.next_reconciliation_at).to be > Time.current
      expect(store.completed?(key)).to be(false)
    end
  end

  describe "fencing with PostgreSQL" do
    let(:key) { "reconciliation-#{SecureRandom.uuid}" }

    before do
      create_operation(key)
    end

    it "completes the operation with a valid reconciliation token" do
      token = lease.acquire(key)

      checker = double("ExternalStatusChecker")

      allow(checker)
        .to receive(:call)
        .with(key: key)
        .and_return(
          status: :confirmed,
          result: { application_id: 123 }
        )

      service = build_service(checker: checker)

      result = service.call(
        key: key,
        reconciliation_token: token
      )

      expect(result).to eq(
        application_id: 123
      )

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      expect(operation.status).to eq("completed")
      expect(operation.result).to eq(
        "application_id" => 123
      )
    end

    it "rejects completion after the lease expires" do
      token = lease.acquire(key)

      operation = JobSearchOperation.find_by!(
        operation_key: key
      )

      operation.update!(
        reconciliation_expires_at: 1.minute.ago
      )

      checker = double("ExternalStatusChecker")

      allow(checker)
        .to receive(:call)
        .with(key: key)
        .and_return(
          status: :confirmed,
          result: { application_id: 456 }
        )

      service = build_service(checker: checker)

      result = service.call(
        key: key,
        reconciliation_token: token
      )

      expect(result).to be_nil

      operation.reload

      expect(operation.status).to eq("uncertain")
      expect(operation.result).to be_nil
    end
  end

  describe "reconciliation scheduling" do
    let(:key) { "reconciliation-#{SecureRandom.uuid}" }

    let(:scheduler) do
      JobSearch::ReconciliationScheduler.new(
        backoff: JobSearch::ReconciliationBackoff.new(
          base_delay: 30,
          max_delay: 300
        )
      )
    end

    let!(:operation) do
      create_operation(key)
    end

    [ :unknown, :not_found ].each do |external_status|
      it "schedules another attempt when status is #{external_status}" do
        token = lease.acquire(key)

        checker = double("ExternalStatusChecker")

        allow(checker)
          .to receive(:call)
          .with(key: key)
          .and_return(status: external_status)

        service = build_service(
          checker: checker,
          scheduler: scheduler
        )

        result = service.call(
          key: key,
          reconciliation_token: token
        )

        expect(result).to be_nil

        operation.reload

        expect(operation.status).to eq("uncertain")

        expect(operation.reconciliation_attempts).to eq(1)

        expect(operation.next_reconciliation_at)
          .to be_within(2.seconds).of(30.seconds.from_now)
      end
    end

    it "does not schedule when the reconciliation token has expired" do
      token = lease.acquire(key)

      operation.update!(
        reconciliation_expires_at: 1.minute.ago
      )

      checker = double("ExternalStatusChecker")

      allow(checker)
        .to receive(:call)
        .with(key: key)
        .and_return(status: :unknown)

      service = build_service(
        checker: checker,
        scheduler: scheduler
      )

      result = service.call(
        key: key,
        reconciliation_token: token
      )

      expect(result).to be_nil

      operation.reload

      expect(operation.status).to eq("uncertain")
      expect(operation.next_reconciliation_at).to be_nil
    end
  end
end

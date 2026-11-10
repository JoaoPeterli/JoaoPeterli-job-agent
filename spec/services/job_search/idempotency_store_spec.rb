require "rails_helper"

RSpec.describe JobSearch::IdempotencyStore do
  describe "#acquire" do
    let(:store) { described_class.new }

    it "returns a token when acquiring a new key" do
      token = store.acquire("action-123")

      expect(token).not_to be_nil
    end

    it "does not acquire a key with an active lease" do
      store.acquire("action-123")

      second_token = store.acquire("action-123")

      expect(second_token).to be_nil
    end

    it "allows acquiring different keys" do
      first_token = store.acquire("action-123")
      second_token = store.acquire("action-456")

      expect(first_token).not_to be_nil
      expect(second_token).not_to be_nil
      expect(first_token).not_to eq(second_token)
    end
  end

  describe "lease expiration" do
    let(:clock) { instance_double(JobSearch::Clock) }

    let(:store) do
      described_class.new(
        ttl_seconds: 30,
        clock: clock
      )
    end

    it "blocks acquisition while the lease is active" do
      allow(clock).to receive(:now).and_return(
        100.0, 120.0
      )

      first_token = store.acquire("action-123")
      second_token = store.acquire("action-123")

      expect(first_token).not_to be_nil
      expect(second_token).to be_nil
    end

    it "allows acquiring a key after the lease expires" do
      allow(clock).to receive(:now).and_return(
        100.0, 131.0
      )

      first_token = store.acquire("action-123")
      second_token = store.acquire("action-123")

      expect(second_token).not_to be_nil
      expect(second_token).not_to eq(first_token)
    end

    it "treats the exact expiration instant as expired" do
      allow(clock).to receive(:now).and_return(
        100.0, 130.0
      )

      first_token = store.acquire("action-123")
      second_token = store.acquire("action-123")

      expect(second_token).not_to be_nil
      expect(second_token).not_to eq(first_token)
    end
  end

  describe "#renew" do
    let(:clock) { instance_double(JobSearch::Clock) }

    let(:store) do
      described_class.new(
        ttl_seconds: 30,
        clock: clock
      )
    end

    it "extends an active lease owned by the token" do
      allow(clock).to receive(:now).and_return(
        100.0, 120.0, 135.0
      )

      token = store.acquire("action-123")

      expect(store.renew("action-123", token)).to eq(true)

      # Original expiration: 130
      # Renewed expiration: 150
      expect(store.acquire("action-123")).to be_nil
    end

    it "rejects renewal with an invalid token" do
      allow(clock).to receive(:now).and_return(
        100.0, 110.0
      )

      store.acquire("action-123")

      expect(
        store.renew("action-123", "invalid-token")
      ).to eq(false)
    end

    it "rejects renewal of an expired lease" do
      allow(clock).to receive(:now).and_return(
        100.0, 131.0
      )

      token = store.acquire("action-123")

      expect(store.renew("action-123", token)).to eq(false)
    end

    it "rejects renewal by the previous owner" do
      allow(clock).to receive(:now).and_return(
        100.0, 131.0, 132.0
      )

      old_token = store.acquire("action-123")
      new_token = store.acquire("action-123")

      expect(new_token).not_to eq(old_token)
      expect(store.renew("action-123", old_token)).to eq(false)
    end
  end

  describe "#release" do
    let(:clock) { instance_double(JobSearch::Clock) }

    let(:store) do
      described_class.new(
        ttl_seconds: 30,
        clock: clock
      )
    end

    it "releases an active lease owned by the token" do
      allow(clock).to receive(:now).and_return(
        100.0, 110.0, 111.0
      )

      token = store.acquire("action-123")

      expect(store.release("action-123", token)).to eq(true)
      expect(store.acquire("action-123")).not_to be_nil
    end

    it "rejects release with an invalid token" do
      allow(clock).to receive(:now).and_return(
        100.0, 110.0, 111.0
      )

      store.acquire("action-123")

      expect(
        store.release("action-123", "invalid-token")
      ).to eq(false)

      expect(store.acquire("action-123")).to be_nil
    end

    it "rejects release of an expired lease" do
      allow(clock).to receive(:now).and_return(
        100.0, 131.0
      )

      token = store.acquire("action-123")

      expect(store.release("action-123", token)).to eq(false)
    end

    it "prevents an old owner from releasing a new lease" do
      allow(clock).to receive(:now).and_return(
        100.0, 131.0, 132.0, 133.0
      )

      old_token = store.acquire("action-123")
      new_token = store.acquire("action-123")

      expect(store.release("action-123", old_token)).to eq(false)
      expect(store.acquire("action-123")).to be_nil

      expect(new_token).not_to eq(old_token)
    end
  end

  describe "#complete" do
    let(:store) { described_class.new }

    it "stores the result of a completed operation" do
      token = store.acquire("action-123")

      result = {
        status: "success",
        job_id: 456
      }

      expect(
        store.complete("action-123", token, result: result)
      ).to eq(true)

      expect(store.completed_result("action-123")).to eq(result)
    end

    it "prevents acquiring an already completed operation" do
      token = store.acquire("action-123")

      store.complete("action-123", token, result: "done")

      expect(store.acquire("action-123")).to be_nil
    end

    it "rejects completion with an invalid token" do
      store.acquire("action-123")

      expect(
        store.complete(
          "action-123",
          "wrong-token",
          result: "done"
        )
      ).to eq(false)

      expect(store.completed_result("action-123")).to be_nil
    end

    it "rejects completion after the lease expires" do
      clock = instance_double(JobSearch::Clock)

      allow(clock).to receive(:now).and_return(
        100.0, 131.0
      )

      store = described_class.new(
        ttl_seconds: 30,
        clock: clock
      )

      token = store.acquire("action-123")

      expect(
        store.complete("action-123", token, result: "done")
      ).to eq(false)
    end

    it "does not allow releasing a completed operation" do
      token = store.acquire("action-123")

      store.complete("action-123", token, result: "done")

      expect(store.release("action-123", token)).to eq(false)
      expect(store.acquire("action-123")).to be_nil
    end
  end

  describe "#completed?" do
    let(:store) { described_class.new }

    it "returns false for an unknown operation" do
      expect(store.completed?("action-123")).to eq(false)
    end

    it "returns false for an active lease" do
      store.acquire("action-123")

      expect(store.completed?("action-123")).to eq(false)
    end

    it "returns true for a completed operation" do
      token = store.acquire("action-123")

      store.complete("action-123", token, result: "done")

      expect(store.completed?("action-123")).to eq(true)
    end

    it "recognizes a completed operation with a nil result" do
      token = store.acquire("action-123")

      store.complete("action-123", token, result: nil)

      expect(store.completed?("action-123")).to eq(true)
      expect(store.completed_result("action-123")).to be_nil
    end
  end

  describe "#reconcile_completed" do
  it "does not overwrite an already reconciled operation" do
    store = described_class.new

    key = "application-123"
    token = store.acquire(key)

    expect(store.mark_uncertain(key, token)).to be(true)

    first_result = {
      application_id: 100,
      status: "submitted"
    }

    second_result = {
      application_id: 200,
      status: "submitted"
    }

    expect(
      store.reconcile_completed(
        key,
        result: first_result
      )
    ).to be(true)

    expect(
      store.reconcile_completed(
        key,
        result: second_result
      )
    ).to be(false)

    expect(store.completed_result(key)).to eq(first_result)
  end
end
end

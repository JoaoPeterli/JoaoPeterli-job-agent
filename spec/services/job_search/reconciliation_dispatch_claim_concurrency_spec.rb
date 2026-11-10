
require "rails_helper"
require "timeout"

RSpec.describe JobSearch::ReconciliationDispatchClaim,
               "PostgreSQL concurrency" do
  self.use_transactional_tests = false

  let(:key) { "concurrent-dispatch-#{SecureRandom.uuid}" }

  before do
    JobSearchOperation.create!(
      operation_key: key,
      status: "uncertain",
      operation_type: "apply_job"
    )
  end

  after do
    JobSearchOperation.where(operation_key: key).delete_all
  end

  it "allows only one worker to acquire the same claim" do
    ready = Queue.new
    start = Queue.new
    results = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          claim = described_class.new(ttl_seconds: 60)

          ready << true
          start.pop

          results << claim.acquire(key)
        end
      end
    end

    Timeout.timeout(10) do
      2.times { ready.pop }
      2.times { start << true }

      threads.each(&:value)
    end

    tokens = 2.times.map { results.pop }

    expect(tokens.compact.size).to eq(1)
    expect(tokens.count(nil)).to eq(1)

    operation = JobSearchOperation.find_by!(
      operation_key: key
    )

    expect(operation.reconciliation_dispatch_token)
      .to eq(tokens.compact.first)
  ensure
    threads&.each do |thread|
      thread.kill if thread.alive?
      thread.join
    end
  end
end

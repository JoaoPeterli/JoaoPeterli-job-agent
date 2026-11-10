require "rails_helper"

RSpec.describe JobSearch::ParallelRunner do
  let(:inline_wrapper) { ->(&work) { work.call } }

  def runner(max_parallel)
    described_class.new(max_parallel: max_parallel, wrapper: inline_wrapper)
  end

  it "returns outcomes in the order of the items, not of completion" do
    outcomes = runner(3).map([ 0.15, 0.0, 0.05 ]) { |delay| sleep(delay); delay }

    expect(outcomes.map(&:value)).to eq([ 0.15, 0.0, 0.05 ])
  end

  it "really runs items at the same time" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    runner(3).map([ 0.2, 0.2, 0.2 ]) { |delay| sleep(delay) }

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 0.45
  end

  it "never runs more than max_parallel items at once" do
    lock = Mutex.new
    running = 0
    peak = 0

    runner(2).map(Array.new(6, 0.03)) do |delay|
      lock.synchronize { running += 1; peak = [ peak, running ].max }
      sleep(delay)
      lock.synchronize { running -= 1 }
    end

    expect(peak).to eq(2)
  end

  it "captures errors per item instead of raising" do
    outcomes = runner(2).map([ 1, 2, 3 ]) { |n| n == 2 ? raise("boom #{n}") : n * 10 }

    expect(outcomes.map(&:ok?)).to eq([ true, false, true ])
    expect(outcomes[1].error.message).to eq("boom 2")
    expect(outcomes.map(&:value)).to eq([ 10, nil, 30 ])
  end

  it "runs inline, on the caller's thread, when max_parallel is 1" do
    threads = runner(1).map([ 1, 2 ]) { Thread.current }

    expect(threads.map(&:value).uniq).to eq([ Thread.current ])
  end

  it "wraps the work of each thread (e.g. the Rails executor)" do
    wrapped = Queue.new
    wrapper = ->(&work) { wrapped << true; work.call }

    described_class.new(max_parallel: 2, wrapper: wrapper).map([ 1, 2 ]) { |n| n }

    expect(wrapped.size).to eq(2)
  end

  it "rejects an invalid limit" do
    expect { described_class.new(max_parallel: 0) }.to raise_error(ArgumentError)
  end
end

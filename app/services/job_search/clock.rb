module JobSearch
  class Clock
    def now
      Process.clock_gettime(
        Process::CLOCK_MONOTONIC
      )
    end
  end
end

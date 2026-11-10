module JobSearch
  # Entrada rejeitada por parecer uma tentativa de prompt injection.
  # Não é retryable: a mesma entrada seria rejeitada de novo.
  class UntrustedInputError < PlanningError
    attr_reader :signals

    def initialize(message, signals: [])
      super(message, retryable: false)
      @signals = signals
    end
  end
end

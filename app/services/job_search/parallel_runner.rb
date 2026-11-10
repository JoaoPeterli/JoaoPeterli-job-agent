module JobSearch
  # Executa um bloco para cada item em até max_parallel threads e devolve
  # os desfechos NA ORDEM DOS ITENS (não na ordem em que terminaram):
  # Outcome(value:) ou Outcome(error:). Nunca lança erro de um item: quem
  # chama decide o que fazer com as falhas (ex.: fail-fast por wave).
  #
  # - Limite de concorrência: protege o provedor de LLM (rate limit/429)
  #   e o pool de conexões do banco.
  # - max_parallel 1 roda tudo na thread atual, em sequência (sem thread).
  # - wrapper envolve o trabalho de cada thread. No Rails, o executor do
  #   Rails libera a conexão do banco e recarrega código com segurança.
  class ParallelRunner
    Outcome = Data.define(:value, :error) do
      def ok? = error.nil?
    end

    RAILS_WRAPPER = ->(&work) { Rails.application.executor.wrap(&work) }

    def initialize(max_parallel:, wrapper: RAILS_WRAPPER)
      raise ArgumentError, "max_parallel must be positive" unless max_parallel.is_a?(Integer) && max_parallel.positive?

      @max_parallel = max_parallel
      @wrapper = wrapper
    end

    def map(items, &work)
      return items.map { |item| outcome { work.call(item) } } if @max_parallel == 1 || items.size <= 1

      outcomes = Array.new(items.size)
      queue = Queue.new
      items.each_with_index { |item, index| queue << [ item, index ] }
      queue.close

      Array.new([ @max_parallel, items.size ].min) do
        Thread.new do
          Thread.current.report_on_exception = false

          while (job = queue.pop)
            item, index = job
            outcomes[index] = outcome { @wrapper.call { work.call(item) } }
          end
        end
      end.each(&:join)

      outcomes
    end

    private

    def outcome
      Outcome.new(value: yield, error: nil)
    rescue StandardError => error
      Outcome.new(value: nil, error: error)
    end
  end
end

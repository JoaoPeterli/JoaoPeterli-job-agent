module JobSearch
  module JobSources
    # Base das fontes de ATS (Greenhouse, Lever, Ashby): um board público por
    # empresa, todos baixados em paralelo. Uma empresa fora do ar (ou com
    # slug errado) é pulada; a fonte só falha se TODAS falharem.
    class CompanyBoards
      COMPANIES_PATH = Rails.root.join("config/job_companies.yml")
      MAX_PARALLEL = 4

      def self.companies(key)
        (YAML.safe_load_file(COMPANIES_PATH)&.fetch(key.to_s, nil) || {}).transform_keys(&:to_s)
      end

      def initialize(fetcher:, companies: self.class.companies(self.class::CONFIG_KEY),
                     runner: ParallelRunner.new(max_parallel: MAX_PARALLEL))
        @fetcher = fetcher
        @companies = companies
        @runner = runner
      end

      def fetch
        return [] if @companies.empty?

        outcomes = @runner.map(@companies.to_a) { |slug, name| board(slug, name) }
        if outcomes.none?(&:ok?)
          raise JobSourceError, "#{self.class::NAME}: every board failed (#{outcomes.first.error.message.truncate(120)})"
        end

        outcomes.select(&:ok?).flat_map(&:value)
      end

      private

      def board(slug, name)
        jobs_in(JSON.parse(@fetcher.get(board_url(slug)))).map { |job| build(job, slug: slug, name: name) }
      rescue JSON::ParserError, TypeError, KeyError => error
        raise JobSourceError, "#{self.class::NAME}/#{slug}: invalid JSON (#{error.class})"
      end

      def remote_text?(text)
        text.to_s.match?(/\b(remote|remoto|remota|anywhere)\b/i)
      end

      def parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end

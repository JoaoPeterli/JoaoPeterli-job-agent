require "nokogiri"

module JobSearch
  module JobSources
    # RSS do We Work Remotely, só as categorias de programação. Termos: uso
    # livre, desde que os links voltem para o We Work Remotely.
    class WeWorkRemotely
      NAME = "We Work Remotely".freeze
      HOMEPAGE = "https://weworkremotely.com".freeze
      FEED_URLS = %w[
        remote-back-end-programming-jobs
        remote-front-end-programming-jobs
        remote-full-stack-programming-jobs
        remote-devops-sysadmin-jobs
      ].map { |category| "https://weworkremotely.com/categories/#{category}.rss" }.freeze

      def initialize(fetcher:, feed_urls: FEED_URLS)
        @fetcher = fetcher
        @feed_urls = feed_urls
      end

      def fetch
        @feed_urls.flat_map { |url| parse(@fetcher.get(url)) }
      end

      private

      def parse(xml)
        document = Nokogiri::XML(xml) { |config| config.strict.nonet }
        document.xpath("//item").map { |item| build(item) }
      rescue Nokogiri::XML::SyntaxError => error
        raise JobSourceError, "#{NAME}: invalid RSS (#{error.message.truncate(80)})"
      end

      # O título vem como "Empresa: Cargo".
      def build(item)
        text = ->(name) { item.at_xpath(name)&.text }
        company, title = text.("title").to_s.split(": ", 2)
        title, company = company, nil if title.nil?

        JobListing.build(
          title: title,
          company: company,
          url: text.("link"),
          source: NAME,
          location: text.("region").presence || "Remoto",
          remote: true,
          published_at: parse_time(text.("pubDate")),
          tags: text.("skills").to_s.split(/,\s*(?:and\s+)?|\s+and\s+/) + [ text.("category") ]
        )
      end

      def parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end

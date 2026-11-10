require "net/http"

module JobSearch
  module JobSources
    # GET com timeouts curtos, limite de tamanho e cache. Cada feed é baixado
    # no máximo uma vez a cada CACHE_TTL: respeita os limites das fontes
    # (RemoteOK, GitHub sem token: 60 req/h) e deixa buscas seguidas rápidas.
    class HttpFetcher
      USER_AGENT = "job-agent/1.0 (portfolio project)".freeze
      OPEN_TIMEOUT = 3
      READ_TIMEOUT = 5
      MAX_BYTES = 8 * 1024 * 1024
      CACHE_TTL = 15.minutes

      def initialize(cache: Rails.cache, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        @cache = cache
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      # A chave do cache é só a URL: credenciais vão nos headers, nunca na
      # URL, e não acabam no cache nem nos logs.
      def get(url, headers: {}, ttl: CACHE_TTL)
        @cache.fetch("job_sources/#{url}", expires_in: ttl) { request(URI(url), headers) }
      end

      private

      def request(uri, headers)
        raise JobSourceError, "only https is allowed: #{uri}" unless uri.is_a?(URI::HTTPS)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                   open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
          http.request(Net::HTTP::Get.new(uri, { "User-Agent" => USER_AGENT }.merge(headers)))
        end

        raise JobSourceError, "#{uri.host} answered HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        body = response.body.to_s
        raise JobSourceError, "#{uri.host} answered more than #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES

        body
      rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => error
        raise JobSourceError, "#{uri.host} unreachable (#{error.class})"
      end
    end
  end
end

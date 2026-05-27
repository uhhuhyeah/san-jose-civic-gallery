require "net/http"
require "time"
require "uri"

module Documents
  # Shared safety perimeter for outbound HTTP fetches against trusted
  # attachment hosts. Handles URL parsing, scheme/host allowlisting,
  # timeouts, redirect bookkeeping, and HTTP-date parsing so that
  # SafeDownloader (streaming GET) and RemoteFileProbe (HEAD) only need
  # to express their request shape and response handling.
  class SafeHttpClient
    class Error < StandardError; end
    class DisallowedHostError < Error; end
    class DisallowedSchemeError < Error; end
    class TooLargeError < Error; end
    class TooManyRedirectsError < Error; end

    class HttpError < Error
      attr_reader :status

      def initialize(message = nil, status: nil)
        super(message)
        @status = status
      end
    end

    DEFAULT_ALLOWED_HOSTS = %w[
      sanjose.legistar.com
      legistar.granicus.com
      www.sanjoseca.gov
    ].freeze
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 30
    MAX_REDIRECTS = 3

    private

    def with_connection(url:)
      uri = parse_uri(url)
      validate_scheme!(uri)
      validate_host!(uri)

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: open_timeout,
        read_timeout: read_timeout
      ) do |http|
        yield(http, uri)
      end
    end

    def resolve_redirect(original_url:, response:, redirects_remaining:)
      raise TooManyRedirectsError, "Too many redirects following #{original_url}" if redirects_remaining <= 0

      location = response["Location"]
      raise HttpError, "Redirect from #{original_url} missing Location header" if location.blank?

      URI.join(original_url, location).to_s
    end

    def parse_uri(url)
      URI.parse(url)
    rescue URI::InvalidURIError => error
      raise Error, "Invalid URL #{url.inspect}: #{error.message}"
    end

    def validate_scheme!(uri)
      return if uri.is_a?(URI::HTTPS)
      return if uri.is_a?(URI::HTTP) && allow_http?

      raise DisallowedSchemeError, "Only HTTPS URLs are allowed: #{uri}"
    end

    def validate_host!(uri)
      return if allowed_hosts.include?(uri.host)

      raise DisallowedHostError, "Host #{uri.host.inspect} is not in the allowlist"
    end

    def allowed_hosts
      configured = ENV["LEGISTAR_ATTACHMENT_ALLOWED_HOSTS"]
      return DEFAULT_ALLOWED_HOSTS if configured.blank?

      configured.split(",").map(&:strip).reject(&:empty?)
    end

    def allow_http?
      ENV["LEGISTAR_ATTACHMENT_ALLOW_HTTP"] == "true"
    end

    def open_timeout
      raw = ENV["LEGISTAR_ATTACHMENT_OPEN_TIMEOUT"]
      Integer(raw, exception: false) || DEFAULT_OPEN_TIMEOUT
    end

    def read_timeout
      raw = ENV["LEGISTAR_ATTACHMENT_READ_TIMEOUT"]
      Integer(raw, exception: false) || DEFAULT_READ_TIMEOUT
    end

    def user_agent
      ENV.fetch("LEGISTAR_USER_AGENT", "SanJoseCivicGallery/1.0 (+mail@davidamcclain.com)")
    end

    def parse_http_time(value)
      return if value.blank?

      Time.httpdate(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

require "digest"
require "net/http"
require "time"
require "uri"

module Documents
  class SafeDownloader
    DEFAULT_ALLOWED_HOSTS = %w[
      sanjose.legistar.com
      legistar.granicus.com
    ].freeze
    DEFAULT_MAX_BYTES = 100 * 1024 * 1024
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 30
    MAX_REDIRECTS = 3

    Result = Struct.new(
      :checksum_sha256,
      :byte_size,
      :content_type,
      :final_url,
      :etag,
      :last_modified_at,
      keyword_init: true
    )

    class Error < StandardError; end
    class DisallowedHostError < Error; end
    class DisallowedSchemeError < Error; end
    class TooLargeError < Error; end
    class TooManyRedirectsError < Error; end
    class HttpError < Error; end

    def self.call(url:, io:)
      new.call(url:, io:)
    end

    def call(url:, io:)
      download(url:, io:, redirects_remaining: MAX_REDIRECTS)
    end

    private

    def download(url:, io:, redirects_remaining:)
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
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = user_agent
        request["Accept"] = "*/*"

        http.request(request) do |response|
          case response
          when Net::HTTPSuccess
            return stream_body(response:, io:, final_url: uri.to_s)
          when Net::HTTPRedirection
            raise TooManyRedirectsError, "Too many redirects following #{url}" if redirects_remaining <= 0

            location = response["Location"]
            raise HttpError, "Redirect from #{url} missing Location header" if location.blank?

            redirect_url = URI.join(url, location).to_s
            return download(url: redirect_url, io:, redirects_remaining: redirects_remaining - 1)
          else
            raise HttpError, "HTTP #{response.code} from #{url}"
          end
        end
      end
    end

    def stream_body(response:, io:, final_url:)
      cap = max_bytes
      declared_length = response["Content-Length"]&.to_i
      if declared_length && declared_length > cap
        raise TooLargeError, "Declared Content-Length #{declared_length} exceeds cap of #{cap}"
      end

      digest = Digest::SHA256.new
      byte_count = 0

      response.read_body do |chunk|
        byte_count += chunk.bytesize
        raise TooLargeError, "Download exceeded cap of #{cap} bytes" if byte_count > cap

        digest.update(chunk)
        io.write(chunk)
      end

      io.flush if io.respond_to?(:flush)

      Result.new(
        checksum_sha256: digest.hexdigest,
        byte_size: byte_count,
        content_type: response["Content-Type"],
        final_url: final_url,
        etag: response["ETag"],
        last_modified_at: parse_http_time(response["Last-Modified"])
      )
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

    def parse_http_time(value)
      return if value.blank?

      Time.httpdate(value)
    rescue ArgumentError
      nil
    end

    def allow_http?
      ENV["LEGISTAR_ATTACHMENT_ALLOW_HTTP"] == "true"
    end

    def max_bytes
      raw = ENV["LEGISTAR_ATTACHMENT_MAX_BYTES"]
      return DEFAULT_MAX_BYTES if raw.blank?

      parsed = Integer(raw, exception: false)
      parsed&.positive? ? parsed : DEFAULT_MAX_BYTES
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
      ENV.fetch("LEGISTAR_USER_AGENT", "SanJoseCivicPulse/1.0 (+mail@davidamcclain.com)")
    end
  end
end

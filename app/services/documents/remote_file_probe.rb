require "net/http"
require "time"
require "uri"

module Documents
  class RemoteFileProbe
    MAX_REDIRECTS = 3

    Result = Struct.new(
      :status,
      :content_length,
      :content_type,
      :etag,
      :last_modified_at,
      :final_url,
      keyword_init: true
    ) do
      def not_modified?
        status == :not_modified
      end
    end

    def self.call(url:, etag: nil, last_modified_at: nil)
      new.call(url:, etag:, last_modified_at:)
    end

    def call(url:, etag: nil, last_modified_at: nil)
      probe(url:, etag:, last_modified_at:, redirects_remaining: MAX_REDIRECTS)
    end

    private

    def probe(url:, etag:, last_modified_at:, redirects_remaining:)
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
        request = Net::HTTP::Head.new(uri)
        request["User-Agent"] = user_agent
        request["Accept"] = "*/*"
        request["If-None-Match"] = etag if etag.present?
        request["If-Modified-Since"] = last_modified_at.httpdate if last_modified_at.present?

        response = http.request(request)
        case response
        when Net::HTTPNotModified
          return result_for(response:, status: :not_modified, final_url: uri.to_s)
        when Net::HTTPSuccess
          return result_for(response:, status: :ok, final_url: uri.to_s)
        when Net::HTTPRedirection
          raise SafeDownloader::TooManyRedirectsError, "Too many redirects following #{url}" if redirects_remaining <= 0

          location = response["Location"]
          raise SafeDownloader::HttpError, "Redirect from #{url} missing Location header" if location.blank?

          redirect_url = URI.join(url, location).to_s
          return probe(url: redirect_url, etag:, last_modified_at:, redirects_remaining: redirects_remaining - 1)
        else
          raise SafeDownloader::HttpError, "HTTP #{response.code} from #{url}"
        end
      end
    end

    def result_for(response:, status:, final_url:)
      Result.new(
        status:,
        content_length: response["Content-Length"]&.to_i,
        content_type: response["Content-Type"],
        etag: response["ETag"],
        last_modified_at: parse_http_time(response["Last-Modified"]),
        final_url:
      )
    end

    def parse_uri(url)
      URI.parse(url)
    rescue URI::InvalidURIError => error
      raise SafeDownloader::Error, "Invalid URL #{url.inspect}: #{error.message}"
    end

    def validate_scheme!(uri)
      return if uri.is_a?(URI::HTTPS)
      return if uri.is_a?(URI::HTTP) && allow_http?

      raise SafeDownloader::DisallowedSchemeError, "Only HTTPS URLs are allowed: #{uri}"
    end

    def validate_host!(uri)
      return if allowed_hosts.include?(uri.host)

      raise SafeDownloader::DisallowedHostError, "Host #{uri.host.inspect} is not in the allowlist"
    end

    def allowed_hosts
      configured = ENV["LEGISTAR_ATTACHMENT_ALLOWED_HOSTS"]
      return SafeDownloader::DEFAULT_ALLOWED_HOSTS if configured.blank?

      configured.split(",").map(&:strip).reject(&:empty?)
    end

    def allow_http?
      ENV["LEGISTAR_ATTACHMENT_ALLOW_HTTP"] == "true"
    end

    def open_timeout
      raw = ENV["LEGISTAR_ATTACHMENT_OPEN_TIMEOUT"]
      Integer(raw, exception: false) || SafeDownloader::DEFAULT_OPEN_TIMEOUT
    end

    def read_timeout
      raw = ENV["LEGISTAR_ATTACHMENT_READ_TIMEOUT"]
      Integer(raw, exception: false) || SafeDownloader::DEFAULT_READ_TIMEOUT
    end

    def user_agent
      ENV.fetch("LEGISTAR_USER_AGENT", "SanJoseCivicPulse/1.0 (+mail@davidamcclain.com)")
    end

    def parse_http_time(value)
      return if value.blank?

      Time.httpdate(value)
    rescue ArgumentError
      nil
    end
  end
end

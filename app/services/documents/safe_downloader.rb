require "digest"
require "net/http"
require "uri"

module Documents
  class SafeDownloader < SafeHttpClient
    DEFAULT_MAX_BYTES = 100 * 1024 * 1024

    Result = Struct.new(
      :checksum_sha256,
      :byte_size,
      :content_type,
      :final_url,
      :etag,
      :last_modified_at,
      keyword_init: true
    )

    def self.call(url:, io:)
      new.call(url:, io:)
    end

    def call(url:, io:)
      download(url:, io:, redirects_remaining: MAX_REDIRECTS)
    end

    private

    def download(url:, io:, redirects_remaining:)
      with_connection(url:) do |http, uri|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = user_agent
        request["Accept"] = "*/*"

        http.request(request) do |response|
          case response
          when Net::HTTPSuccess
            return stream_body(response:, io:, final_url: uri.to_s)
          when Net::HTTPRedirection
            redirect_url = resolve_redirect(original_url: url, response:, redirects_remaining:)
            return download(url: redirect_url, io:, redirects_remaining: redirects_remaining - 1)
          else
            status = response.code.to_i
            error_class = status.between?(500, 599) ? HttpServerError : HttpError
            raise error_class.new("HTTP #{response.code} from #{url}", status: status)
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

    def max_bytes
      raw = ENV["LEGISTAR_ATTACHMENT_MAX_BYTES"]
      return DEFAULT_MAX_BYTES if raw.blank?

      parsed = Integer(raw, exception: false)
      parsed&.positive? ? parsed : DEFAULT_MAX_BYTES
    end
  end
end

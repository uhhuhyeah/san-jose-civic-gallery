require "net/http"

module Documents
  class RemoteFileProbe < SafeHttpClient
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
      with_connection(url:) do |http, uri|
        request = Net::HTTP::Head.new(uri)
        request["User-Agent"] = user_agent
        request["Accept"] = "*/*"
        request["If-None-Match"] = etag if etag.present?
        request["If-Modified-Since"] = last_modified_at.httpdate if last_modified_at.present?

        response = http.request(request)
        case response
        when Net::HTTPNotModified
          result_for(response:, status: :not_modified, final_url: uri.to_s)
        when Net::HTTPSuccess
          result_for(response:, status: :ok, final_url: uri.to_s)
        when Net::HTTPRedirection
          redirect_url = resolve_redirect(original_url: url, response:, redirects_remaining:)
          probe(url: redirect_url, etag:, last_modified_at:, redirects_remaining: redirects_remaining - 1)
        else
          status = response.code.to_i
          error_class = status.between?(500, 599) ? HttpServerError : HttpError
          raise error_class.new("HTTP #{response.code} from #{url}", status: status)
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
  end
end

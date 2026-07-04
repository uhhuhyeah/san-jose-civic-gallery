require "digest"
require "json"
require "net/http"
require "uri"

module Legistar
  class Client
    # Base class for all Legistar HTTP failures. Services and jobs can rescue
    # this broadly; ApplicationJob retries the transient subclass below.
    class Error < StandardError; end

    # 5xx — upstream is temporarily broken. Retried by ApplicationJob.
    class HttpServerError < Error
      attr_reader :status, :url

      def initialize(status:, url:)
        @status = status
        @url = url
        super("Legistar request failed with status #{status} for #{url}")
      end
    end

    # 4xx — the request itself is wrong (bad id, forbidden, gone). Not retried;
    # retrying would keep failing the same way.
    class HttpClientError < Error
      attr_reader :status, :url

      def initialize(status:, url:)
        @status = status
        @url = url
        super("Legistar request failed with status #{status} for #{url}")
      end
    end

    # Any other non-2xx status (1xx/3xx leaking through, non-standard codes).
    # Treated as transient and retried so an unexpected response doesn't
    # permanently lose a sync.
    class HttpError < Error
      attr_reader :status, :url

      def initialize(status:, url:)
        @status = status
        @url = url
        super("Legistar request failed with status #{status} for #{url}")
      end
    end

    DEFAULT_BASE_URL = "https://webapi.legistar.com/v1/sanjose"
    DEFAULT_SOURCE_SYSTEM = "legistar.sanjose"
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 30
    DEFAULT_USER_AGENT = "SanJoseCivicGallery/1.0 (+mail@davidamcclain.com)"

    attr_reader :source_system

    def initialize(source_system: nil)
      @source_system = source_system || ENV.fetch("LEGISTAR_SOURCE_SYSTEM", DEFAULT_SOURCE_SYSTEM)
    end

    def recent_events(limit: 10, body_name: "City Council")
      params = {
        "$orderby" => "EventDate desc",
        "$top" => limit
      }

      if body_name.present?
        params["$filter"] = "EventBodyName eq '#{body_name.gsub("'", "''")}'"
      end

      get("Events", params:)
    end

    def events_for_window(body_name:, start_date:, end_date:, limit:, skip: 0)
      params = {
        "$filter" => [
          "EventBodyName eq '#{escape_odata_string(body_name)}'",
          "EventDate ge #{odata_datetime(start_date)}",
          "EventDate lt #{odata_datetime(end_date)}"
        ].join(" and "),
        # Secondary EventId key keeps pagination stable when multiple
        # events share the same EventDate.
        "$orderby" => "EventDate asc, EventId asc",
        "$top" => limit,
        "$skip" => skip
      }

      get("Events", params:)
    end

    def event_items(event_id:)
      get("Events/#{event_id}/EventItems")
    end

    def matter(matter_id:)
      get("Matters/#{matter_id}")
    end

    def matter_attachments(matter_id:)
      get("Matters/#{matter_id}/Attachments")
    end

    # Raise the appropriate Error subclass for a non-200 response. Callers
    # that already branch on status can keep doing so; this consolidates the
    # "is this transient?" classification in one place so ApplicationJob can
    # retry 5xx without retrying permanent 4xx failures.
    def assert_ok!(response)
      status = response[:status]
      return if status == 200

      raise self.class.error_for(status, response[:request_url])
    end

    # Public so jobs that do their own HTTP (e.g.
    # SyncRecentEventsForAllBodiesJob hitting /Bodies directly) can raise the
    # same classified error without instantiating a client.
    def self.error_for(status, url)
      case status
      when 500..599 then HttpServerError.new(status:, url:)
      when 400..499 then HttpClientError.new(status:, url:)
      else HttpError.new(status:, url:)
      end
    end

    private

    def escape_odata_string(value)
      value.to_s.gsub("'", "''")
    end

    def odata_datetime(value)
      date = value.is_a?(Date) ? value : Date.iso8601(value.to_s)
      "datetime'#{date.iso8601}T00:00:00'"
    end

    def get(path, params: {})
      uri = URI.join("#{base_url}/", path)
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: open_timeout,
        read_timeout: read_timeout
      ) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = user_agent
        request["Accept"] = "application/json"
        http.request(request)
      end

      body = response.body.presence || "[]"

      {
        request_url: uri.to_s,
        status: response.code.to_i,
        fetched_at: Time.current,
        response_sha256: Digest::SHA256.hexdigest(body),
        payload: JSON.parse(body)
      }
    end

    def base_url
      ENV.fetch("LEGISTAR_API_BASE_URL", DEFAULT_BASE_URL)
    end

    def open_timeout
      Integer(ENV["LEGISTAR_OPEN_TIMEOUT"], exception: false) || DEFAULT_OPEN_TIMEOUT
    end

    def read_timeout
      Integer(ENV["LEGISTAR_READ_TIMEOUT"], exception: false) || DEFAULT_READ_TIMEOUT
    end

    def user_agent
      ENV.fetch("LEGISTAR_USER_AGENT", DEFAULT_USER_AGENT)
    end
  end
end

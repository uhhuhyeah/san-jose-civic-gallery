require "digest"
require "json"
require "net/http"
require "uri"

module Legistar
  class Client
    DEFAULT_BASE_URL = "https://webapi.legistar.com/v1/sanjose"
    DEFAULT_SOURCE_SYSTEM = "legistar.sanjose"
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 30
    DEFAULT_USER_AGENT = "SanJoseCivicPulse/1.0 (+mail@davidamcclain.com)"

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
        "$orderby" => "EventDate asc",
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

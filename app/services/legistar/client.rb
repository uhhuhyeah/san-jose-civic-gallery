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

require "digest"
require "json"
require "net/http"
require "uri"

module Legistar
  class Client
    BASE_URL = ENV.fetch("LEGISTAR_API_BASE_URL", "https://webapi.legistar.com/v1/sanjose")

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
      uri = URI.join("#{BASE_URL}/", path)
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(Net::HTTP::Get.new(uri))
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
  end
end

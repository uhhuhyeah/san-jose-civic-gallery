require "digest"
require "net/http"
require "uri"

module Iqm2
  # Plain-HTTP IQM2 client for discovery (RSS calendar) and one meeting's web
  # agenda (HTML). Mirrors Legistar::Client's Net::HTTP + provenance envelope,
  # but keeps the raw body (RSS/HTML) instead of parsing JSON. Attachment PDF
  # downloads do NOT go through this client; they use the shared document
  # download pipeline once the host is allowlisted (a later PR).
  class Client
    # Raised by callers when a fetch returns a non-200 status, so a blocked or
    # error response becomes a recorded failure instead of being parsed as if it
    # were the feed.
    class ResponseError < StandardError; end

    DEFAULT_BASE_URL = "https://sccgov.iqm2.com"
    DEFAULT_SOURCE_SYSTEM = "iqm2.sccgov"
    DEFAULT_OPEN_TIMEOUT = 5
    DEFAULT_READ_TIMEOUT = 30
    DEFAULT_USER_AGENT = "SanJoseCivicGallery/1.0 (+mail@davidamcclain.com)"

    attr_reader :source_system

    def initialize(source_system: nil)
      @source_system = source_system || ENV.fetch("IQM2_SOURCE_SYSTEM", DEFAULT_SOURCE_SYSTEM)
    end

    # Discovery: the RSS meeting calendar (newest first).
    def meeting_listing
      get("/Services/RSS.aspx", params: { "Feed" => "Calendar" })
    end

    # Date-ranged discovery for historical backfill. NOT YET WIRED: no parser
    # consumes this and nothing calls it. It returns the /Citizens/calendar.aspx
    # List-view HTML page, which has a DIFFERENT DOM from the RSS feed, so its
    # payload must NOT be passed to Iqm2::MeetingCalendar.parse. Beware: that
    # page contains the literal text "Meeting Calendar", which is one of the two
    # signatures MeetingCalendar.parse's blocked-feed guard accepts, so feeding
    # it there would silently pass the guard and yield near-zero refs instead of
    # raising. A deep historical backfill needs its own calendar-page parser.
    def calendar(from:, to:)
      get("/Citizens/calendar.aspx", params: { "From" => us_date(from), "To" => us_date(to), "View" => "List" })
    end

    # One meeting's full web agenda (HTML).
    def meeting_detail(meeting_id:)
      get("/Citizens/Detail_Meeting.aspx", params: { "ID" => meeting_id })
    end

    private

    def us_date(value)
      date = value.is_a?(Date) ? value : Date.parse(value.to_s)
      "#{date.month}/#{date.day}/#{date.year}"
    end

    def get(path, params: {})
      uri = URI.join("#{base_url}/", path.sub(%r{\A/}, ""))
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
        request["Accept"] = "text/html"
        http.request(request)
      end

      body = response.body.to_s

      {
        request_url: uri.to_s,
        status: response.code.to_i,
        fetched_at: Time.current,
        response_sha256: Digest::SHA256.hexdigest(body),
        payload: body
      }
    end

    def base_url
      ENV.fetch("IQM2_API_BASE_URL", DEFAULT_BASE_URL)
    end

    def open_timeout
      Integer(ENV["IQM2_OPEN_TIMEOUT"], exception: false) || DEFAULT_OPEN_TIMEOUT
    end

    def read_timeout
      Integer(ENV["IQM2_READ_TIMEOUT"], exception: false) || DEFAULT_READ_TIMEOUT
    end

    def user_agent
      ENV.fetch("IQM2_USER_AGENT", DEFAULT_USER_AGENT)
    end
  end
end

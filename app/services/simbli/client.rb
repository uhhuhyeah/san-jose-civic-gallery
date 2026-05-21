require "open3"
require "json"
require "digest"
require "timeout"

module Simbli
  # Browser-backed Simbli fetcher. Shells out to the Node Playwright script
  # (lib/simbli/fetch.mjs), which loads a meeting in one browser session and
  # returns its agenda tree plus supporting documents. The fragile anti-bot
  # logic lives in the script; this class is a thin adapter that produces the
  # hash contract SyncMeeting expects and turns failures (including an Incapsula
  # interstitial) into raised errors so a blocked fetch never looks like an
  # empty-but-successful sync.
  #
  # One Node invocation per meeting; both agenda_tree and supporting_documents
  # are served from that single cached result.
  class Client
    class FetchError < StandardError; end
    class BlockedError < FetchError; end

    SCRIPT = Rails.root.join("lib/simbli/fetch.mjs").to_s
    DEFAULT_SCHOOL_ID = "36030421".freeze
    DEFAULT_TIMEOUT = 120

    # `capture` is the process-runner seam: a callable taking the meeting id and
    # returning [stdout, stderr, Process::Status]. Defaults to shelling out to
    # the Node script; tests inject a fake.
    def initialize(school_id: DEFAULT_SCHOOL_ID, node_bin: ENV.fetch("SIMBLI_NODE_BIN", "node"), timeout: DEFAULT_TIMEOUT, capture: nil)
      @school_id = school_id
      @node_bin = node_bin
      @timeout = timeout
      @capture = capture || method(:shell_capture)
      @meetings = {}
    end

    def agenda_tree(mid:)
      contract(payload: fetch_meeting(mid).fetch("agenda"), mid: mid)
    end

    def supporting_documents(mid:, agenda_id:)
      docs = fetch_meeting(mid).fetch("supportingDocuments", {})[agenda_id.to_s] || { "Attachment" => [] }
      contract(payload: docs, mid: mid)
    end

    private

    def fetch_meeting(mid)
      @meetings[mid.to_s] ||= run_meeting(mid)
    end

    def run_meeting(mid)
      stdout, stderr, status = @capture.call(mid)
      raise FetchError, "simbli fetch exited #{status.exitstatus}: #{stderr.to_s.strip}" unless status.success?

      data = JSON.parse(stdout.presence || "{}")
      raise BlockedError, "simbli anti-bot block: #{data['blockedBy']}" if data["blocked"]
      raise FetchError, (data["error"].presence || "simbli fetch failed") unless data["ok"]

      data
    rescue JSON::ParserError => e
      raise FetchError, "simbli fetch returned invalid JSON: #{e.message}"
    end

    def shell_capture(mid)
      Timeout.timeout(@timeout) do
        Open3.capture3({ "SCHOOL_ID" => @school_id }, @node_bin, SCRIPT, "meeting", mid.to_s)
      end
    rescue Timeout::Error
      raise FetchError, "simbli fetch timed out after #{@timeout}s for MID #{mid}"
    end

    def contract(payload:, mid:)
      {
        request_url: Identifiers.meeting_url(school_id: @school_id, mid: mid),
        status: 200,
        fetched_at: Time.current,
        response_sha256: Digest::SHA256.hexdigest(payload.to_json),
        payload: payload
      }
    end
  end
end

require "open3"
require "json"
require "digest"
require "timeout"

module Simbli
  # Browser-backed Simbli fetcher. Shells out to the Node Playwright script
  # (lib/simbli/fetch.mjs) for the meeting listing and for a meeting's agenda
  # tree plus supporting documents. The fragile anti-bot logic lives in the
  # script; this class is a thin adapter that produces the hash contract the
  # sync services expect and turns failures (including an Incapsula
  # interstitial) into raised errors so a blocked fetch never looks like an
  # empty-but-successful sync.
  #
  # One Node invocation per meeting (and one for the listing); agenda_tree and
  # supporting_documents are served from the single cached meeting result.
  class Client
    class FetchError < StandardError; end
    class BlockedError < FetchError; end

    SCRIPT = Rails.root.join("lib/simbli/fetch.mjs").to_s
    DEFAULT_SCHOOL_ID = "36030421".freeze
    DEFAULT_TIMEOUT = 120

    # `capture` is the process-runner seam: a callable taking the script args
    # array and returning [stdout, stderr, Process::Status]. Defaults to
    # shelling out to the Node script; tests inject a fake.
    def initialize(school_id: DEFAULT_SCHOOL_ID, node_bin: ENV.fetch("SIMBLI_NODE_BIN", "node"), timeout: DEFAULT_TIMEOUT, capture: nil)
      @school_id = school_id
      @node_bin = node_bin
      @timeout = timeout
      @capture = capture || method(:shell_capture)
      @meetings = {}
    end

    def meeting_listing
      contract(payload: listing.fetch("rows", []), url: Identifiers.listing_url(school_id: @school_id))
    end

    def agenda_tree(mid:)
      contract(payload: meeting(mid).fetch("agenda"), url: Identifiers.meeting_url(school_id: @school_id, mid: mid))
    end

    def supporting_documents(mid:, agenda_id:)
      docs = meeting(mid).fetch("supportingDocuments", {})[agenda_id.to_s] || { "Attachment" => [] }
      contract(payload: docs, url: Identifiers.meeting_url(school_id: @school_id, mid: mid))
    end

    private

    def listing
      @listing ||= run("listing")
    end

    def meeting(mid)
      @meetings[mid.to_s] ||= run("meeting", mid.to_s)
    end

    def run(*args)
      stdout, stderr, status = @capture.call(args)
      raise FetchError, "simbli fetch exited #{status.exitstatus}: #{stderr.to_s.strip}" unless status.success?

      data = JSON.parse(stdout.presence || "{}")
      raise BlockedError, "simbli anti-bot block: #{data['blockedBy']}" if data["blocked"]
      raise FetchError, (data["error"].presence || "simbli fetch failed") unless data["ok"]

      data
    rescue JSON::ParserError => e
      raise FetchError, "simbli fetch returned invalid JSON: #{e.message}"
    end

    def shell_capture(args)
      Timeout.timeout(@timeout) do
        Open3.capture3({ "SCHOOL_ID" => @school_id }, @node_bin, SCRIPT, *args)
      end
    rescue Timeout::Error
      raise FetchError, "simbli fetch timed out after #{@timeout}s (args: #{args.join(' ')})"
    end

    def contract(payload:, url:)
      {
        request_url: url,
        status: 200,
        fetched_at: Time.current,
        response_sha256: Digest::SHA256.hexdigest(payload.to_json),
        payload: payload
      }
    end
  end
end

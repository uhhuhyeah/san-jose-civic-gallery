module Simbli
  # Parses the SB_MeetingListing page's meeting links into meeting descriptors.
  #
  # NOTE: the listing table also carries the meeting date/time, but the
  # feasibility spike only captured the anchors (mid + type), not the row date.
  # The live listing client (browser slice) must extract event_date from the
  # table row; it is supplied to persistence separately, not produced here.
  class MeetingListing
    Meeting = Data.define(:school_id, :mid, :meeting_type)

    VIEW_MEETING = /ViewMeeting\(\s*["'](?<school_id>\d+)["']\s*,\s*["'](?<mid>\d+)["']/

    def self.parse(payload)
      entries = payload.is_a?(Hash) ? payload["meetings"] : payload
      Array(entries).filter_map do |entry|
        match = VIEW_MEETING.match(entry["onclick"].to_s)
        next unless match

        Meeting.new(
          school_id: match[:school_id],
          mid: match[:mid],
          meeting_type: entry["text"].to_s.strip
        )
      end
    end
  end
end

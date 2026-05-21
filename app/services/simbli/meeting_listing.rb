module Simbli
  # Parses the SB_MeetingListing page's meeting links into meeting descriptors.
  #
  # The anchor text is the meeting's Title (the clickable meeting name).
  #
  # NOTE: the listing table also carries a separate Meeting Type column and the
  # meeting date/time, but the feasibility spike only captured the anchors
  # (title + ids), not those columns. The live listing client (browser slice)
  # must extract meeting_type and event_date from the table row; they are
  # supplied to persistence separately, not produced here. Title and Type are
  # kept distinct because special rows (e.g. a financing corporation meeting)
  # have a specific Title but a generic Type.
  class MeetingListing
    Meeting = Data.define(:school_id, :mid, :meeting_title)

    VIEW_MEETING = /ViewMeeting\(\s*["'](?<school_id>\d+)["']\s*,\s*["'](?<mid>\d+)["']/

    def self.parse(payload)
      entries = payload.is_a?(Hash) ? payload["meetings"] : payload
      Array(entries).filter_map do |entry|
        match = VIEW_MEETING.match(entry["onclick"].to_s)
        next unless match

        Meeting.new(
          school_id: match[:school_id],
          mid: match[:mid],
          meeting_title: entry["text"].to_s.strip
        )
      end
    end
  end
end

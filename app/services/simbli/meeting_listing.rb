module Simbli
  # Turns the listing command's rows into meeting descriptors. Each row carries
  # the ViewMeeting onclick (school + meeting id) and its cells keyed by header
  # text. Columns are matched by header keyword (date / title / type) rather
  # than fixed position, so minor header wording or column-order changes do not
  # break it. Title and Type are kept distinct (special rows have a specific
  # title but a generic type). Rows whose date cannot be parsed yield a nil
  # event_date and are skipped by the sync loop.
  class MeetingListing
    Meeting = Data.define(:school_id, :mid, :meeting_title, :meeting_type, :event_date)

    VIEW_MEETING = /ViewMeeting\(\s*["'](?<school_id>\d+)["']\s*,\s*["'](?<mid>\d+)["']/
    US_DATE = %r{(?<m>\d{1,2})/(?<d>\d{1,2})/(?<y>\d{4})}

    def self.parse(payload)
      rows = payload.is_a?(Hash) ? payload["rows"] : payload
      Array(rows).filter_map do |row|
        match = VIEW_MEETING.match(row["onclick"].to_s)
        next unless match

        cells = row["cells"] || {}
        title = column(cells, "title").presence || row["text"].to_s.strip

        Meeting.new(
          school_id: match[:school_id],
          mid: match[:mid],
          meeting_title: title,
          meeting_type: column(cells, "type").presence || title,
          event_date: parse_date(column(cells, "date"))
        )
      end
    end

    def self.column(cells, keyword)
      pair = cells.find { |header, _| header.to_s.downcase.include?(keyword) }
      pair ? pair.last.to_s.strip : ""
    end
    private_class_method :column

    def self.parse_date(value)
      match = US_DATE.match(value.to_s)
      return Date.new(match[:y].to_i, match[:m].to_i, match[:d].to_i) if match

      Date.parse(value.to_s)
    rescue Date::Error, TypeError
      nil
    end
    private_class_method :parse_date
  end
end

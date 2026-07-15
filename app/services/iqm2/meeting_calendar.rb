require "nokogiri"

module Iqm2
  # Turns the RSS calendar payload into meeting refs. media_type is the feed's
  # Agenda/Minutes/Webcast classification (NOT the meeting kind); the sync layer
  # filters to media_type == "Agenda". Entries without a Detail_Meeting link
  # (webcast-only) are skipped.
  class MeetingCalendar
    class ParseError < StandardError; end

    MeetingRef = Data.define(:meeting_id, :body_name, :media_type, :event_date, :agenda_file_id, :published_at)

    def self.parse(payload)
      # The IQM2 RSS feed declares encoding="utf-16" in its XML prolog but is
      # actually UTF-8 on the wire, where Net::HTTP hands us an ASCII-8BIT body.
      # Left alone, Nokogiri honors the bogus declaration and mis-parses the
      # document into an empty tree (zero refs / guard trips). Force UTF-8 so the
      # real content is parsed regardless of the lying prolog. (Fixtures read
      # from disk are already UTF-8, which is why this only bit in production.)
      doc = Nokogiri::HTML(payload.to_s, nil, "UTF-8")

      # A blocked, empty, or interstitial response must be a recorded failure,
      # never an empty-but-successful discovery pass (the sync layer would
      # otherwise log "enqueued 0" forever while the portal serves 500s). A
      # genuinely quiet feed still carries its "Meeting Calendar" heading and is
      # allowed to yield zero refs; a response with neither the heading nor any
      # meeting link is not the feed.
      unless recognizable_feed?(doc)
        raise ParseError, "IQM2 calendar: response is not a recognizable meeting feed"
      end

      doc.css("div").filter_map do |div|
        heading = div.at_css("h2")&.text&.strip
        next if heading.blank?

        detail = div.css("a").find { |a| a["href"].to_s =~ /Detail_Meeting\.aspx\?ID=/i }
        next unless detail

        before, _, date_text = heading.rpartition(" - ")
        body_name, _, media_type = before.rpartition(" - ")

        MeetingRef.new(
          meeting_id: detail["href"][/[?&]ID=(\d+)/i, 1],
          body_name: body_name.strip,
          media_type: media_type.strip,
          event_date: parse_date(date_text),
          agenda_file_id: agenda_file_id(div),
          published_at: parse_published(div)
        )
      end
    end

    # The feed's signature: the calendar heading, or at least one meeting-detail
    # link. An "Access Denied", error, or empty page has neither.
    def self.recognizable_feed?(doc)
      return true if doc.text.match?(/Meeting Calendar/i)

      doc.css("a").any? { |a| a["href"].to_s.match?(/Detail_Meeting\.aspx\?ID=/i) }
    end
    private_class_method :recognizable_feed?

    def self.agenda_file_id(div)
      link = div.css("a").find { |a| a["href"].to_s =~ /FileOpen\.aspx\?Type=14&ID=(\d+)/i }
      link ? link["href"][/[?&]ID=(\d+)/i, 1] : nil
    end
    private_class_method :agenda_file_id

    def self.parse_date(text)
      Date.parse(text.to_s)
    rescue Date::Error, TypeError
      nil
    end
    private_class_method :parse_date

    def self.parse_published(div)
      match = div.text[/Published on:\s*([^\n<]+)/i, 1]
      match ? Time.parse(match.strip) : nil
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :parse_published
  end
end

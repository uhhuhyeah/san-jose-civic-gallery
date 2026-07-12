require "nokogiri"

module Iqm2
  # Turns the RSS calendar payload into meeting refs. media_type is the feed's
  # Agenda/Minutes/Webcast classification (NOT the meeting kind); the sync layer
  # filters to media_type == "Agenda". Entries without a Detail_Meeting link
  # (webcast-only) are skipped.
  class MeetingCalendar
    MeetingRef = Data.define(:meeting_id, :body_name, :media_type, :event_date, :agenda_file_id, :published_at)

    def self.parse(payload)
      doc = Nokogiri::HTML(payload.to_s)

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

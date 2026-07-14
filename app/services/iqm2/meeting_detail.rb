require "nokogiri"

module Iqm2
  class MeetingDetail
    class ParseError < StandardError; end

    Meeting = Data.define(:meeting_id, :body_name, :meeting_type, :event_date, :location)
    AgendaItem = Data.define(:legifile_id, :item_number, :title, :attachments)
    Attachment = Data.define(:type, :file_id, :title, :url)

    Result = Data.define(:meeting, :agenda_items)

    def self.parse(payload)
      doc = Nokogiri::HTML(payload.to_s)
      table = doc.at_css("table#MeetingDetail")
      raise ParseError, "IQM2 meeting detail: no MeetingDetail table" if table.nil?

      items = extract_items(table)
      raise ParseError, "IQM2 meeting detail: zero agenda items" if items.empty?

      Result.new(meeting: extract_meeting(doc, table), agenda_items: items)
    end

    def self.extract_meeting(doc, table)
      date_text = text(doc, "#ContentPlaceholder1_lblMeetingDate")
      Meeting.new(
        meeting_id: table.to_s[/MeetingID=(\d+)/i, 1],
        body_name: text(doc, "#ContentPlaceholder1_lblMeetingGroup"),
        meeting_type: text(doc, "#ContentPlaceholder1_lblMeetingType"),
        event_date: parse_date(date_text),
        location: doc.at_css(".MeetingAddress")&.text&.strip
      )
    end
    private_class_method :extract_meeting

    def self.extract_items(table)
      items = []
      current = nil

      table.css("tr").each do |row|
        title_cell = row.at_css("td.Title")
        next unless title_cell

        link = title_cell.at_css("a")
        href = link&.[]("href").to_s

        if href =~ /Detail_LegiFile\.aspx/i
          current = AgendaItem.new(
            legifile_id: href[/[?&]ID=(\d+)/i, 1],
            item_number: item_number(row),
            title: link.text.strip,
            attachments: []
          )
          items << current
        elsif href =~ /FileOpen\.aspx/i && current
          attachment = build_attachment(href, link.text.strip)
          current.attachments << attachment if attachment
        else
          # Any other titled row -- a section header, a motion/vote link, or an
          # unrecognized link -- ends the current item's attachment context, so a
          # following attachment can never be misattributed across a section
          # boundary to the item above it.
          current = nil
        end
      end

      items
    end
    private_class_method :extract_items

    def self.build_attachment(href, title)
      type = href[/[?&]Type=(\d+)/i, 1]
      file_id = href[/[?&]ID=(\d+)/i, 1]
      return nil if type.nil? || file_id.nil? || type == "1"

      Attachment.new(type: type, file_id: file_id, title: title, url: Identifiers.absolute_url(href))
    end
    private_class_method :build_attachment

    def self.item_number(row)
      row.at_css("td.Num")&.text.to_s.strip.sub(/\.\s*\z/, "").strip.presence
    end
    private_class_method :item_number

    def self.text(doc, selector)
      doc.at_css(selector)&.text&.strip
    end
    private_class_method :text

    def self.parse_date(text)
      Date.strptime(text.to_s, "%m/%d/%Y")
    rescue ArgumentError, TypeError
      (Date.parse(text.to_s) rescue nil)
    end
    private_class_method :parse_date
  end
end

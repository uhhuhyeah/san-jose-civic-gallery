module Iqm2
  # Centralizes IQM2 (Santa Clara County / Accela Legislative Management)
  # identity and URL conventions so parsers and (later) persistence agree.
  #
  # Identity uses stable numeric IQM2 ids. A LegiFile ID is a GLOBAL legislative
  # file id (the Detail_LegiFile URL passes MeetingID as separate context), so a
  # matter's source id is the bare LegiFile id and can recur across meetings.
  # An event item is meeting-local, so it is the composite "meetingId:legifileId".
  # An attachment is identified by the "type:fileId" pair that its FileOpen URL
  # carries.
  module Identifiers
    SOURCE_SYSTEM = "iqm2.sccgov".freeze
    BASE_URL = "https://sccgov.iqm2.com".freeze
    CITIZENS_BASE = "https://sccgov.iqm2.com/Citizens/".freeze

    module_function

    def event_source_id(meeting_id:)
      meeting_id.to_s
    end

    def event_item_source_id(meeting_id:, legifile_id:)
      "#{meeting_id}:#{legifile_id}"
    end

    # Bare LegiFile id: a legislative file is global across meetings.
    def matter_source_id(legifile_id:)
      legifile_id.to_s
    end

    # Matches the FileOpen URL's Type/ID pair.
    def attachment_source_id(type:, file_id:)
      "#{type}:#{file_id}"
    end

    def meeting_detail_url(meeting_id:)
      "#{CITIZENS_BASE}Detail_Meeting.aspx?ID=#{meeting_id}"
    end

    def legifile_url(meeting_id:, legifile_id:)
      "#{CITIZENS_BASE}Detail_LegiFile.aspx?MeetingID=#{meeting_id}&ID=#{legifile_id}"
    end

    def file_open_url(type:, file_id:, meeting_id: nil)
      url = "#{CITIZENS_BASE}FileOpen.aspx?Type=#{type}&ID=#{file_id}"
      url += "&MeetingID=#{meeting_id}" if meeting_id
      url
    end

    # Resolve a relative href from a Citizens/ page into an absolute URL.
    def absolute_url(href)
      URI.join(CITIZENS_BASE, href).to_s
    end
  end
end

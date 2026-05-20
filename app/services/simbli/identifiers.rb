module Simbli
  # Centralizes the Simbli identity and URL conventions so parsers, persistence,
  # and (later) the browser client agree.
  #
  # Durable identity uses only the stable numeric ids Simbli's public interface
  # requires together: the school id (S), meeting id (MID), the agenda item's
  # numeric AgendaID, and the numeric AttachmentID. The encrypted/session-scoped
  # ids (item ID, EncrId, sct/endid/...) are never persisted as identity.
  module Identifiers
    SOURCE_SYSTEM = "simbli.sjusd".freeze
    ATTACHMENT_BASE_URL = "https://simbli.eboardsolutions.com/Meetings/Attachment.aspx".freeze
    MEETING_BASE_URL = "https://simbli.eboardsolutions.com/SB_Meetings/ViewMeeting.aspx".freeze

    # Simbli has no clean governing-body field, so SJUSD meetings get a
    # deliberate default body. The Meeting Type is preserved separately.
    DEFAULT_BODY_NAME = "Board of Education".freeze

    module_function

    def meeting_url(school_id:, mid:)
      "#{MEETING_BASE_URL}?S=#{school_id}&MID=#{mid}"
    end

    def event_source_id(school_id:, mid:)
      "#{school_id}:#{mid}"
    end

    def event_item_source_id(school_id:, mid:, agenda_id:)
      "#{school_id}:#{mid}:#{agenda_id}"
    end

    # A synthetic matter is created per agenda item that carries documents, so
    # it shares the agenda item's composite identity.
    def matter_source_id(school_id:, mid:, agenda_id:)
      "#{school_id}:#{mid}:#{agenda_id}"
    end

    def attachment_source_id(school_id:, mid:, attachment_id:)
      "#{school_id}:#{mid}:#{attachment_id}"
    end

    # Prefixed so it never collides with a Legistar matter_file.
    def matter_file(mid:, agenda_id:)
      "SJUSD-#{mid}-#{agenda_id}"
    end

    def attachment_url(school_id:, mid:, attachment_id:)
      "#{ATTACHMENT_BASE_URL}?S=#{school_id}&AID=#{attachment_id}&MID=#{mid}"
    end
  end
end

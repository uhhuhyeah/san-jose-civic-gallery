namespace :simbli do
  desc "Sync one SJUSD Simbli meeting inline (manual trial). " \
       "Required: MID, DATE (YYYY-MM-DD). Optional: TITLE, TYPE, SCHOOL_ID."
  task sync_meeting: :environment do
    mid = ENV.fetch("MID")
    event_date = Date.parse(ENV.fetch("DATE"))
    school_id = ENV.fetch("SCHOOL_ID", Simbli::Client::DEFAULT_SCHOOL_ID)
    title = ENV["TITLE"].presence || "Board Meeting"
    type = ENV["TYPE"].presence || title

    event = Ingestion::Simbli::SyncMeeting.call(
      school_id: school_id,
      mid: mid,
      meeting_title: title,
      meeting_type: type,
      event_date: event_date,
      client: Simbli::Client.new(school_id: school_id)
    )

    warn "Synced SJUSD meeting MID=#{mid} -> Civic::Event ##{event.id}"
    warn "  jurisdiction: #{event.civic_jurisdiction.slug}"
    warn "  agenda items: #{Civic::EventItem.where(civic_event_id: event.id).count}"
    warn "  matters:      #{Civic::Matter.where(source_system: Simbli::Identifiers::SOURCE_SYSTEM).count}"
    warn "  attachments:  #{Civic::MatterAttachment.where(source_system: Simbli::Identifiers::SOURCE_SYSTEM).count}"
  end
end

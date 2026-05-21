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

    puts "Synced SJUSD meeting MID=#{mid} -> Civic::Event ##{event.id}"
    puts "  jurisdiction: #{event.civic_jurisdiction.slug}"
    puts "  agenda items: #{Civic::EventItem.where(civic_event_id: event.id).count}"
    puts "  matters:      #{Civic::Matter.where(source_system: Simbli::Identifiers::SOURCE_SYSTEM).count}"
    puts "  attachments:  #{Civic::MatterAttachment.where(source_system: Simbli::Identifiers::SOURCE_SYSTEM).count}"
  end

  desc "Discover SJUSD meetings from the listing and enqueue per-meeting syncs " \
       "on the simbli_ingestion queue. Optional: LIMIT, SCHOOL_ID."
  task sync_meetings: :environment do
    limit = ENV["LIMIT"].presence&.to_i
    school_id = ENV.fetch("SCHOOL_ID", Simbli::Client::DEFAULT_SCHOOL_ID)

    enqueued = Ingestion::Simbli::SyncMeetings.call(
      client: Simbli::Client.new(school_id: school_id),
      limit: limit
    )

    puts "Enqueued #{enqueued.size} SJUSD meeting sync(s) on simbli_ingestion: #{enqueued.join(', ')}"
  end

  desc "Dump the parsed Simbli listing without persisting (inspect discovery). " \
       "Optional: SCHOOL_ID."
  task dump_listing: :environment do
    school_id = ENV.fetch("SCHOOL_ID", Simbli::Client::DEFAULT_SCHOOL_ID)
    meetings = Simbli::MeetingListing.parse(Simbli::Client.new(school_id: school_id).meeting_listing[:payload])

    puts "Parsed #{meetings.size} meeting(s):"
    meetings.each do |meeting|
      puts "  MID=#{meeting.mid} date=#{meeting.event_date || 'UNPARSED'} " \
           "title=#{meeting.meeting_title.inspect} type=#{meeting.meeting_type.inspect}"
    end
  end
end

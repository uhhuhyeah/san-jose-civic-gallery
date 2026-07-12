namespace :iqm2 do
  desc "Sync one Santa Clara County IQM2 meeting inline (manual trial). Required: MEETING_ID."
  task sync_meeting: :environment do
    meeting_id = ENV.fetch("MEETING_ID")

    event = Ingestion::Iqm2::SyncMeeting.call(
      meeting_id: meeting_id,
      client: Iqm2::Client.new
    )

    puts "Synced IQM2 meeting ID=#{meeting_id} -> Civic::Event ##{event.id}"
    puts "  jurisdiction: #{event.civic_jurisdiction.slug}"
    puts "  agenda items: #{Civic::EventItem.where(civic_event_id: event.id).count}"
    puts "  matters:      #{Civic::Matter.where(source_system: Iqm2::Identifiers::SOURCE_SYSTEM).count}"
    puts "  attachments:  #{Civic::MatterAttachment.where(source_system: Iqm2::Identifiers::SOURCE_SYSTEM).count}"
  end

  desc "Discover Santa Clara County meetings from the RSS calendar and enqueue " \
       "per-meeting syncs on the iqm2_ingestion queue. Optional: LIMIT."
  task sync_meetings: :environment do
    limit = ENV["LIMIT"].presence&.to_i

    enqueued = Ingestion::Iqm2::SyncMeetings.call(
      client: Iqm2::Client.new,
      limit: limit
    )

    puts "Enqueued #{enqueued.size} IQM2 meeting sync(s) on iqm2_ingestion: #{enqueued.join(', ')}"
  end

  desc "Dump the parsed IQM2 RSS calendar without persisting (inspect discovery)."
  task dump_listing: :environment do
    refs = Iqm2::MeetingCalendar.parse(Iqm2::Client.new.meeting_listing[:payload])

    puts "Parsed #{refs.size} calendar entr(ies):"
    refs.first(50).each do |ref|
      puts "  ID=#{ref.meeting_id || 'NONE'} date=#{ref.event_date || 'UNPARSED'} " \
           "media=#{ref.media_type.inspect} body=#{ref.body_name.inspect}"
    end
  end
end

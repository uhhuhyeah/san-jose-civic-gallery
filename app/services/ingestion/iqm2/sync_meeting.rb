module Ingestion
  module Iqm2
    # Ingests a single IQM2 meeting: fetch the web agenda, persist the event, its
    # real matters (LegiFiles), event items, and attachment metadata, then
    # reconcile within the meeting (items/attachments no longer present upstream
    # are tombstoned). A blocked or empty page raises in the parser rather than
    # persisting an empty meeting. The client is injected so tests supply a fake.
    class SyncMeeting
      def self.call(meeting_id:, client:, event_date: nil)
        detail = client.meeting_detail(meeting_id: meeting_id)
        unless detail[:status] == 200
          raise ::Iqm2::Client::ResponseError, "IQM2 meeting #{meeting_id} returned HTTP #{detail[:status]}"
        end

        fetched_at = detail[:fetched_at]
        parsed = ::Iqm2::MeetingDetail.parse(detail[:payload])
        meeting = parsed.meeting

        event, snapshot = PersistMeeting.call(
          meeting_id: meeting_id,
          body_name: meeting.body_name,
          meeting_type: meeting.meeting_type,
          event_date: meeting.event_date || event_date,
          location: meeting.location,
          request_url: detail[:request_url],
          fetched_at: fetched_at,
          http_status: detail[:status],
          response_sha256: detail[:response_sha256],
          payload: detail[:payload]
        )

        seen_item_ids = []
        seen_attachment_ids = []

        parsed.agenda_items.each_with_index do |item, position|
          event_item, attachment_ids = PersistAgendaItem.call(
            event: event,
            item: item,
            meeting_id: meeting_id,
            position: position,
            snapshot: snapshot,
            fetched_at: fetched_at,
            response_sha256: detail[:response_sha256]
          )
          seen_item_ids << event_item.source_event_item_id
          seen_attachment_ids.concat(attachment_ids)
        end

        reconcile_missing_event_items(event:, seen_item_ids:, fetched_at:)
        reconcile_missing_attachments(event:, seen_attachment_ids:, fetched_at:)

        event
      end

      def self.reconcile_missing_event_items(event:, seen_item_ids:, fetched_at:)
        scope = Civic::EventItem.where(civic_event_id: event.id, source_present: true)
        scope = scope.where.not(source_event_item_id: seen_item_ids) if seen_item_ids.any?

        scope.update_all(source_present: false, source_missing_at: fetched_at, updated_at: Time.current)
      end
      private_class_method :reconcile_missing_event_items

      # A LegiFile (matter) is global and recurs across meetings, and each
      # meeting's page lists only its own subset of that file's attachments
      # (confirmed against real data: the same LegiFile shows different
      # attachment sets on two meetings). Tombstoning by matter across all
      # meetings would let syncing one meeting delete attachments legitimately
      # present via another, dropping real data during the historical backfill.
      # So only reconcile attachments of matters referenced solely by THIS event;
      # a matter shared with another event keeps its attachments (they accrue as
      # the file's full document set) until that other meeting is re-synced.
      def self.reconcile_missing_attachments(event:, seen_attachment_ids:, fetched_at:)
        matter_ids = Civic::EventItem
          .where(civic_event_id: event.id)
          .where.not(civic_matter_id: nil)
          .distinct
          .pluck(:civic_matter_id)
        return if matter_ids.empty?

        shared_matter_ids = Civic::EventItem
          .where(civic_matter_id: matter_ids)
          .where.not(civic_event_id: event.id)
          .distinct
          .pluck(:civic_matter_id)
        exclusive_matter_ids = matter_ids - shared_matter_ids
        return if exclusive_matter_ids.empty?

        scope = Civic::MatterAttachment.where(civic_matter_id: exclusive_matter_ids, source_present: true)
        scope = scope.where.not(source_attachment_id: seen_attachment_ids) if seen_attachment_ids.any?

        scope.update_all(source_present: false, source_missing_at: fetched_at, updated_at: Time.current)
      end
      private_class_method :reconcile_missing_attachments
    end
  end
end

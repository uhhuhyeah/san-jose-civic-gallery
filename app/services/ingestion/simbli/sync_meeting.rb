module Ingestion
  module Simbli
    # Orchestrates ingestion of a single Simbli meeting: persist the meeting,
    # its agenda items, and the supporting documents for attachment-bearing
    # items, then reconcile anything that disappeared upstream.
    #
    # The client is injected (duck-typed) so the browser-backed fetcher can drop
    # in later; tests supply a fake returning captured payloads.
    #
    # Client contract (each returns a hash with :request_url, :status,
    # :fetched_at, :response_sha256, :payload):
    #   client.agenda_tree(mid:)
    #   client.supporting_documents(mid:, agenda_id:)
    #
    # Reconciliation here is within a meeting: agenda items and attachments that
    # are no longer present in the fetched agenda/documents are tombstoned
    # (source_present: false). Meetings disappearing from the listing are
    # reconciled by the listing-driven sync (not yet built). Synthetic matters
    # are not tombstoned, matching the Legistar matter behavior.
    class SyncMeeting
      def self.call(school_id:, mid:, meeting_title:, meeting_type:, event_date:, client:)
        agenda = client.agenda_tree(mid: mid)
        fetched_at = agenda[:fetched_at]

        event, snapshot = PersistMeeting.call(
          school_id: school_id,
          mid: mid,
          meeting_title: meeting_title,
          meeting_type: meeting_type,
          event_date: event_date,
          request_url: agenda[:request_url],
          fetched_at: fetched_at,
          http_status: agenda[:status],
          response_sha256: agenda[:response_sha256],
          payload: agenda[:payload]
        )

        seen_item_ids = []
        seen_attachment_ids = []

        ::Simbli::AgendaTree.parse(agenda[:payload]).each do |item|
          event_item = PersistAgendaItem.call(
            event: event,
            item: item,
            school_id: school_id,
            mid: mid,
            snapshot: snapshot,
            fetched_at: fetched_at,
            response_sha256: agenda[:response_sha256]
          )
          seen_item_ids << event_item.source_event_item_id

          next unless item.has_attachment

          seen_attachment_ids.concat(
            sync_supporting_documents(client:, event_item:, school_id:, mid:, item:)
          )
        end

        reconcile_missing_event_items(event:, seen_item_ids:, fetched_at:)
        reconcile_missing_attachments(event:, seen_attachment_ids:, fetched_at:)

        event
      end

      # Returns the source ids of the attachments seen for this item (empty when
      # the item has none, so reconciliation tombstones any it used to have).
      def self.sync_supporting_documents(client:, event_item:, school_id:, mid:, item:)
        docs = client.supporting_documents(mid: mid, agenda_id: item.agenda_id)
        attachments = ::Simbli::SupportingDocuments.parse(docs[:payload])
        return [] if attachments.empty?

        PersistSupportingDocuments.call(
          event_item: event_item,
          school_id: school_id,
          mid: mid,
          agenda_id: item.agenda_id,
          item_title: item.title,
          attachments: attachments,
          request_url: docs[:request_url],
          fetched_at: docs[:fetched_at],
          http_status: docs[:status],
          response_sha256: docs[:response_sha256],
          payload: docs[:payload]
        )

        attachments.map do |doc|
          ::Simbli::Identifiers.attachment_source_id(school_id: school_id, mid: mid, attachment_id: doc.attachment_id)
        end
      end
      private_class_method :sync_supporting_documents

      def self.reconcile_missing_event_items(event:, seen_item_ids:, fetched_at:)
        scope = Civic::EventItem.where(civic_event_id: event.id, source_present: true)
        scope = scope.where.not(source_event_item_id: seen_item_ids) if seen_item_ids.any?

        scope.update_all(source_present: false, source_missing_at: fetched_at, updated_at: Time.current)
      end
      private_class_method :reconcile_missing_event_items

      def self.reconcile_missing_attachments(event:, seen_attachment_ids:, fetched_at:)
        matter_ids = Civic::EventItem
          .where(civic_event_id: event.id)
          .where.not(civic_matter_id: nil)
          .select(:civic_matter_id)

        scope = Civic::MatterAttachment.where(civic_matter_id: matter_ids, source_present: true)
        scope = scope.where.not(source_attachment_id: seen_attachment_ids) if seen_attachment_ids.any?

        scope.update_all(source_present: false, source_missing_at: fetched_at, updated_at: Time.current)
      end
      private_class_method :reconcile_missing_attachments
    end
  end
end

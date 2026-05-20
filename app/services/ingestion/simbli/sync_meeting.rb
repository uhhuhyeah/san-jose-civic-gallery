module Ingestion
  module Simbli
    # Orchestrates ingestion of a single Simbli meeting: persist the meeting,
    # its agenda items, and the supporting documents for attachment-bearing
    # items. The client is injected (duck-typed) so the browser-backed fetcher
    # can drop in later; tests supply a fake returning captured payloads.
    #
    # Client contract (each returns a hash with :request_url, :status,
    # :fetched_at, :response_sha256, :payload):
    #   client.agenda_tree(mid:)
    #   client.supporting_documents(mid:, agenda_id:)
    class SyncMeeting
      def self.call(school_id:, mid:, meeting_type:, event_date:, client:)
        agenda = client.agenda_tree(mid: mid)

        event, snapshot = PersistMeeting.call(
          school_id: school_id,
          mid: mid,
          meeting_type: meeting_type,
          event_date: event_date,
          request_url: agenda[:request_url],
          fetched_at: agenda[:fetched_at],
          http_status: agenda[:status],
          response_sha256: agenda[:response_sha256],
          payload: agenda[:payload]
        )

        ::Simbli::AgendaTree.parse(agenda[:payload]).each do |item|
          event_item = PersistAgendaItem.call(
            event: event,
            item: item,
            school_id: school_id,
            mid: mid,
            snapshot: snapshot,
            fetched_at: agenda[:fetched_at],
            response_sha256: agenda[:response_sha256]
          )

          next unless item.has_attachment

          sync_supporting_documents(client:, event_item:, school_id:, mid:, item:)
        end

        event
      end

      def self.sync_supporting_documents(client:, event_item:, school_id:, mid:, item:)
        docs = client.supporting_documents(mid: mid, agenda_id: item.agenda_id)
        attachments = ::Simbli::SupportingDocuments.parse(docs[:payload])
        return if attachments.empty?

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
      end
      private_class_method :sync_supporting_documents
    end
  end
end

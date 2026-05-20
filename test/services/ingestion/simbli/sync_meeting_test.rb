require "test_helper"

module Ingestion
  module Simbli
    class SyncMeetingTest < ActiveSupport::TestCase
      setup do
        @agenda = JSON.parse(file_fixture("simbli/agenda_tree.json").read)
        @docs = JSON.parse(file_fixture("simbli/supporting_documents.json").read)
        @client = FakeClient.new(agenda: @agenda, docs: @docs)
      end

      test "persists the meeting as an SJUSD-jurisdiction event" do
        event = sync

        assert_equal "simbli.sjusd", event.source_system
        assert_equal "sjusd", event.civic_jurisdiction.slug
        assert_equal "36030421:57394", event.source_event_id
        assert_equal "Board of Education", event.body_name
        assert_equal "Regular Session Board Meeting", event.source_meeting_type
        assert_equal Date.new(2026, 4, 23), event.event_date
      end

      test "persists all agenda items in agenda order" do
        event = sync

        items = Civic::EventItem.where(civic_event_id: event.id).order(:agenda_sequence)
        assert_equal(
          [ "36030421:57394:100", "36030421:57394:101", "36030421:57394:200", "36030421:57394:201" ],
          items.map(&:source_event_item_id)
        )
      end

      test "creates a synthetic matter and attachments for attachment-bearing items" do
        sync

        item = Civic::EventItem.find_by(source_event_item_id: "36030421:57394:201")
        assert_not_nil item.civic_matter_id

        matter = item.matter
        assert_equal "SJUSD-57394-201", matter.matter_file
        assert_equal "sjusd", matter.civic_jurisdiction.slug

        attachments = matter.all_attachments.reorder(:sort_order)
        assert_equal [ "36030421:57394:5001", "36030421:57394:5002" ], attachments.map(&:source_attachment_id)
        assert_includes attachments.first.hyperlink, "Attachment.aspx?S=36030421&AID=5001&MID=57394"
        assert_equal "Gift Acceptance Memo", attachments.first.name
      end

      test "agenda items without attachments get no matter" do
        sync

        item = Civic::EventItem.find_by(source_event_item_id: "36030421:57394:100")
        assert_nil item.civic_matter_id
      end

      test "records meeting and supporting-document source snapshots" do
        sync

        assert Ingestion::SourceSnapshot.exists?(
          source_system: "simbli.sjusd", resource_type: "meeting", source_id: "36030421:57394"
        )
        assert Ingestion::SourceSnapshot.exists?(
          source_system: "simbli.sjusd", resource_type: "supporting_documents", source_id: "36030421:57394:201"
        )
      end

      test "is idempotent across repeated syncs" do
        sync

        assert_no_difference [ "Civic::Event.count", "Civic::EventItem.count", "Civic::Matter.count", "Civic::MatterAttachment.count" ] do
          sync
        end
      end

      private

      def sync
        SyncMeeting.call(
          school_id: "36030421",
          mid: "57394",
          meeting_type: "Regular Session Board Meeting",
          event_date: Date.new(2026, 4, 23),
          client: @client
        )
      end

      class FakeClient
        def initialize(agenda:, docs:)
          @agenda = agenda
          @docs = docs
        end

        def agenda_tree(mid:)
          { request_url: "https://example.test/agenda/#{mid}", status: 200, fetched_at: Time.current, response_sha256: "agenda-sha", payload: @agenda }
        end

        def supporting_documents(mid:, agenda_id:)
          { request_url: "https://example.test/docs/#{mid}/#{agenda_id}", status: 200, fetched_at: Time.current, response_sha256: "docs-#{agenda_id}", payload: @docs }
        end
      end
    end
  end
end

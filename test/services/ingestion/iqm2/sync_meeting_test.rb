require "test_helper"

module Ingestion
  module Iqm2
    class SyncMeetingTest < ActiveSupport::TestCase
      setup do
        @detail = file_fixture("iqm2/sync_meeting_detail.html").read
        @reduced = file_fixture("iqm2/sync_meeting_detail_reduced.html").read
        @item2_no_attachments = file_fixture("iqm2/sync_meeting_detail_item2_no_attachments.html").read
      end

      test "persists the meeting as a Santa Clara County event" do
        event = sync

        assert_equal "iqm2.sccgov", event.source_system
        assert_equal "santaclaracounty", event.civic_jurisdiction.slug
        assert_equal "8001", event.source_event_id
        assert_equal "Board of Supervisors", event.body_name
        assert_equal "Regular Meeting", event.source_meeting_type
        assert_equal Date.new(2026, 6, 23), event.event_date
        assert_includes event.location_name, "70 West Hedding Street"
      end

      test "persists every agenda item as a real matter in agenda order" do
        event = sync

        items = Civic::EventItem.where(civic_event_id: event.id).order(:agenda_sequence)
        assert_equal [ "8001:500", "8001:501" ], items.map(&:source_event_item_id)
        assert items.all? { |item| item.civic_matter_id.present? }
        assert_equal "1", items.first.agenda_number
      end

      test "creates real matters keyed by the bare LegiFile id" do
        sync

        matter = Civic::Matter.find_by(source_system: "iqm2.sccgov", source_matter_id: "500")
        assert_not_nil matter
        assert_equal "SCC-500", matter.matter_file
        assert_equal "santaclaracounty", matter.civic_jurisdiction.slug
        assert_equal "Board of Supervisors", matter.body_name
        assert_includes matter.title, "Approve minutes"
      end

      test "persists attachment metadata for attachment-bearing items" do
        sync

        matter = Civic::Matter.find_by(source_matter_id: "501")
        attachments = matter.all_attachments.reorder(:sort_order)

        assert_equal [ "30:9001", "30:9002" ], attachments.map(&:source_attachment_id)
        assert_equal "Staff Report", attachments.first.name
        assert_includes attachments.first.hyperlink, "FileOpen.aspx?Type=30&ID=9001"
        assert_equal true, attachments.first.is_supporting_document
      end

      test "items without attachments still get a matter but no attachments" do
        sync

        matter = Civic::Matter.find_by(source_matter_id: "500")
        assert_not_nil matter
        assert_empty matter.all_attachments
      end

      test "records a meeting source snapshot" do
        sync

        assert Ingestion::SourceSnapshot.exists?(
          source_system: "iqm2.sccgov",
          resource_type: "meeting",
          source_id: "8001"
        )
      end

      test "is idempotent across repeated syncs" do
        sync

        assert_no_difference [ "Civic::Event.count", "Civic::EventItem.count", "Civic::Matter.count", "Civic::MatterAttachment.count" ] do
          sync
        end
      end

      test "tombstones agenda items and their attachments removed from the agenda" do
        sync

        sync(html: @reduced)

        assert Civic::EventItem.find_by(source_event_item_id: "8001:500").source_present
        assert_not Civic::EventItem.find_by(source_event_item_id: "8001:501").source_present
        assert_not Civic::MatterAttachment.find_by(source_attachment_id: "30:9001").source_present
      end

      test "tombstones attachments removed from an item while the item remains" do
        sync

        sync(html: @item2_no_attachments)

        assert Civic::EventItem.find_by(source_event_item_id: "8001:501").source_present
        assert_not Civic::MatterAttachment.find_by(source_attachment_id: "30:9001").source_present
        assert_not Civic::MatterAttachment.find_by(source_attachment_id: "30:9002").source_present
      end

      test "raises on a non-200 meeting response instead of persisting an event" do
        bad_client = Class.new do
          def meeting_detail(meeting_id:)
            { request_url: "https://example.test/#{meeting_id}", status: 503, fetched_at: Time.current, response_sha256: "s", payload: "<html>error</html>" }
          end
        end.new

        assert_raises(::Iqm2::Client::ResponseError) do
          SyncMeeting.call(meeting_id: "8001", client: bad_client)
        end
        assert_not Civic::Event.exists?(source_system: "iqm2.sccgov", source_event_id: "8001")
      end

      test "does not tombstone a shared matter's attachments when re-syncing another meeting" do
        shared_a = file_fixture("iqm2/sync_shared_a.html").read
        shared_b = file_fixture("iqm2/sync_shared_b.html").read

        # LegiFile 700 appears on meetings 8100 and 8200 with different attachment
        # sets (8100 shows 30:7001 and 4:7002; 8200 shows only 4:7002).
        SyncMeeting.call(meeting_id: "8100", event_date: Date.new(2026, 6, 18), client: FakeClient.new(shared_a))
        SyncMeeting.call(meeting_id: "8200", event_date: Date.new(2026, 6, 23), client: FakeClient.new(shared_b))

        # Syncing 8200 must not tombstone 30:7001, which is legitimately present
        # via 8100. Both remain, so the matter carries the file's full doc set.
        assert Civic::MatterAttachment.find_by(source_attachment_id: "30:7001").source_present
        assert Civic::MatterAttachment.find_by(source_attachment_id: "4:7002").source_present

        matter = Civic::Matter.find_by(source_matter_id: "700")
        assert_equal [ "30:7001", "4:7002" ], matter.all_attachments.reorder(:source_attachment_id).pluck(:source_attachment_id)
      end

      test "enqueues a download job for each new attachment" do
        assert_enqueued_jobs 2, only: Documents::ImportMatterAttachmentFileJob do
          sync
        end
      end

      test "does not re-enqueue a download for an already-imported attachment" do
        sync
        imported = Civic::MatterAttachment.find_by(source_attachment_id: "30:9001")
        imported.source_file.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "a.pdf", content_type: "application/pdf")

        # Only 30:9002 (still not imported) should re-enqueue; 30:9001 is skipped.
        assert_enqueued_jobs 1, only: Documents::ImportMatterAttachmentFileJob do
          sync
        end
      end

      private

      def sync(html = @detail)
        SyncMeeting.call(
          meeting_id: "8001",
          event_date: Date.new(2026, 6, 23),
          client: FakeClient.new(html)
        )
      end

      class FakeClient
        def initialize(html)
          @html = html
        end

        def meeting_detail(meeting_id:)
          {
            request_url: "https://example.test/meeting/#{meeting_id}",
            status: 200,
            fetched_at: Time.current,
            response_sha256: "detail-sha",
            payload: @html
          }
        end
      end
    end
  end
end

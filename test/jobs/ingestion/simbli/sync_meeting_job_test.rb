require "test_helper"

module Ingestion
  module Simbli
    class SyncMeetingJobTest < ActiveSupport::TestCase
      test "enqueues on the simbli_ingestion queue" do
        assert_enqueued_with(queue: "simbli_ingestion") do
          SyncMeetingJob.perform_later(
            school_id: "36030421", mid: "57394",
            meeting_title: "Board Meeting", meeting_type: "Regular Session Board Meeting",
            event_date: Date.new(2026, 4, 23)
          )
        end
      end

      test "performs the sync with an injected client" do
        agenda = JSON.parse(file_fixture("simbli/agenda_tree.json").read)
        docs = JSON.parse(file_fixture("simbli/supporting_documents.json").read)

        SyncMeetingJob.perform_now(
          school_id: "36030421", mid: "57394",
          meeting_title: "Board Meeting", meeting_type: "Regular Session Board Meeting",
          event_date: Date.new(2026, 4, 23),
          client: FakeClient.new(agenda: agenda, docs: docs)
        )

        assert Civic::Event.exists?(source_system: "simbli.sjusd", source_event_id: "36030421:57394")
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

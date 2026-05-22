require "test_helper"

module Generated
  class BackfillEventSummariesTest < ActiveSupport::TestCase
    setup do
      @client = FakeClient.new
    end

    test "only events with published minutes are candidates" do
      with_minutes = create_event(legistar_event_id: 82_001, minutes_status_name: "Final")
      with_file = create_event(legistar_event_id: 82_002, minutes_file_uri: "https://example.test/minutes.pdf")
      draft = create_event(legistar_event_id: 82_003, minutes_status_name: "Draft")

      result = BackfillEventSummaries.call(limit: 10, dry_run: true, client: @client)
      ids = result.candidates.map(&:id)

      assert_includes ids, with_minutes.id
      assert_includes ids, with_file.id
      assert_not_includes ids, draft.id
    end

    test "dry run does not call the model" do
      create_event(legistar_event_id: 82_010, minutes_status_name: "Final")

      result = BackfillEventSummaries.call(limit: 10, dry_run: true, client: @client)

      assert_equal 1, result.candidates.size
      assert_equal 0, @client.calls
      assert_equal 0, result.generated
    end

    test "running generates summaries and then skips already-summarized events" do
      create_event(legistar_event_id: 82_020, minutes_status_name: "Final")

      first = BackfillEventSummaries.call(limit: 10, dry_run: false, client: @client)
      assert_equal 1, first.generated

      second = BackfillEventSummaries.call(limit: 10, dry_run: false, client: @client)
      assert_equal 0, second.candidates.size
      assert_equal 1, @client.calls
    end

    test "scopes to a single jurisdiction when given" do
      sanjose = create_event(legistar_event_id: 82_030, minutes_status_name: "Final")
      Civic::Event.create!(
        source_system: "simbli.sjusd",
        source_event_id: "sjusd-evt-82031",
        body_name: "Board of Education",
        event_date: Date.current,
        minutes_status_name: "Final"
      ).all_event_items.create!(source_system: "simbli.sjusd", source_event_item_id: "sjusd-item-1", title: "Budget", minutes_note: "Discussed budget.", agenda_sequence: 1)

      result = BackfillEventSummaries.call(limit: 10, dry_run: true, client: @client, jurisdiction: sanjose.civic_jurisdiction)

      assert_equal [ sanjose.id ], result.candidates.map(&:id)
    end

    private

    def create_event(legistar_event_id:, minutes_status_name: nil, minutes_file_uri: nil)
      event = Civic::Event.create!(
        legistar_event_id:,
        body_name: "City Council",
        title: "Regular Meeting",
        event_date: Date.new(2026, 5, 12),
        minutes_status_name:,
        minutes_file_uri:
      )
      event.all_event_items.create!(
        legistar_event_item_id: legistar_event_id + 500_000,
        agenda_number: "3.1",
        title: "Housing item",
        minutes_note: "Council discussed the housing item.",
        agenda_sequence: 1
      )
      event
    end

    class FakeClient
      attr_reader :calls, :model_name, :max_input_chars

      def initialize
        @calls = 0
        @model_name = "test-event-model"
        @max_input_chars = 18_000
      end

      def call(system_prompt:, user_prompt:)
        @calls += 1
        EventSummaryClient::Response.new(
          model_name:,
          content: { "summary" => "Summary.", "key_topics" => [], "limitations" => [] },
          usage_metadata: {}
        )
      end
    end
  end
end

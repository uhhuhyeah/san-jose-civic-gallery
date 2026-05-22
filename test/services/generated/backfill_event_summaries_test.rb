require "test_helper"

module Generated
  class BackfillEventSummariesTest < ActiveSupport::TestCase
    setup do
      @client = FakeClient.new
    end

    test "only events with agenda items are candidates" do
      with_items = create_event(legistar_event_id: 82_001)
      empty = create_event(legistar_event_id: 82_003, with_item: false)

      result = BackfillEventSummaries.call(limit: 10, dry_run: true, client: @client)
      ids = result.candidates.map(&:id)

      assert_includes ids, with_items.id
      assert_not_includes ids, empty.id
    end

    test "dry run does not call the model" do
      create_event(legistar_event_id: 82_010)

      result = BackfillEventSummaries.call(limit: 10, dry_run: true, client: @client)

      assert_equal 1, result.candidates.size
      assert_equal 0, @client.calls
      assert_equal 0, result.generated
    end

    test "running generates summaries and then skips already-summarized events" do
      create_event(legistar_event_id: 82_020)

      first = BackfillEventSummaries.call(limit: 10, dry_run: false, client: @client)
      assert_equal 1, first.generated

      second = BackfillEventSummaries.call(limit: 10, dry_run: false, client: @client)
      assert_equal 0, second.candidates.size
      assert_equal 1, @client.calls
    end

    test "scopes to a single jurisdiction when given" do
      sanjose = create_event(legistar_event_id: 82_030)
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

    def create_event(legistar_event_id:, with_item: true)
      event = Civic::Event.create!(
        legistar_event_id:,
        body_name: "City Council",
        title: "Regular Meeting",
        event_date: Date.new(2026, 5, 12),
        agenda_status_name: "Final"
      )
      if with_item
        event.all_event_items.create!(
          legistar_event_item_id: legistar_event_id + 500_000,
          agenda_number: "3.1",
          title: "Approve affordable housing agreement",
          agenda_sequence: 1
        )
      end
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

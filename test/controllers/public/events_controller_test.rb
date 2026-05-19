require "test_helper"

module Public
  class EventsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = Civic::Event.create!(
        legistar_event_id: 7621,
        body_name: "City Council",
        title: "Regular meeting",
        event_date: Date.new(2026, 5, 12),
        agenda_status_name: "Final",
        minutes_status_name: "Draft"
      )

      @event.event_items.create!(
        legistar_event_item_id: 129630,
        agenda_sequence: 1,
        title: "Public Comment",
        matter_file: "CC 1.1"
      )
    end

    test "gets the index" do
      get root_url

      assert_response :success
      assert_includes response.body, "San Jose Civic Gallery"
      assert_includes response.body, "Welcome to San Jose Civic Gallery"
      assert_includes response.body, "Regular meeting"
      assert_includes response.body, "Agenda: Final"
      assert_includes response.body, "Minutes: Draft"
    end

    test "shows an event" do
      get public_event_url(@event)

      assert_response :success
      assert_includes response.body, public_meetings_path(month: "2026-05")
      assert_includes response.body, "Regular meeting"
      assert_includes response.body, "City Council"
      assert_includes response.body, "Public Comment"
    end

    test "event detail returns 304 when client ETag matches" do
      get public_event_url(@event)
      assert_response :success
      etag = response.headers["ETag"]

      get public_event_url(@event), headers: { "If-None-Match" => etag }

      assert_response :not_modified
    end

    test "homepage emits cacheable Cache-Control and no Set-Cookie" do
      get root_url

      assert_response :success
      cache_control = response.headers["Cache-Control"]
      assert_includes cache_control, "public"
      assert_includes cache_control, "max-age=300"
      assert_includes cache_control, "s-maxage=7200"
      assert_nil response.headers["Set-Cookie"],
        "expected no Set-Cookie on anonymous public GET (got #{response.headers["Set-Cookie"].inspect})"
    end

    test "renders matter-pending hint when item has matter_id but no synced matter" do
      @event.event_items.create!(
        legistar_event_item_id: 129631,
        agenda_sequence: 2,
        title: "Pending matter item",
        matter_id: 99999,
        matter_file: "CC 9.9"
      )

      get public_event_url(@event)

      assert_response :success
      assert_includes response.body, "Linked matter sync pending"
      assert_includes response.body, "CC 9.9"
    end

    test "eager-loads items, matters, and attachments" do
      matter_a = Civic::Matter.create!(legistar_matter_id: 18001, matter_file: "26-A")
      matter_b = Civic::Matter.create!(legistar_matter_id: 18002, matter_file: "26-B")
      matter_c = Civic::Matter.create!(legistar_matter_id: 18003, matter_file: "26-C")

      [ matter_a, matter_b, matter_c ].each_with_index do |matter, i|
        @event.event_items.create!(
          legistar_event_item_id: 200_000 + i,
          agenda_sequence: 10 + i,
          title: "Item #{i}",
          civic_matter_id: matter.id,
          matter_id: matter.legistar_matter_id
        )
        matter.all_attachments.create!(legistar_matter_attachment_id: 300_000 + i, name: "Att #{i}")
      end

      queries = count_app_queries { get public_event_url(@event) }

      assert_response :success
      assert_operator queries.size, :<=, 10,
        "Expected events#show to issue at most 10 SQL queries (4 eager-load + 6 cache-version); got #{queries.size}:\n#{queries.join("\n")}"
    end

    private

    def count_app_queries
      queries = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:name].to_s =~ /\A(SCHEMA|TRANSACTION|EXPLAIN)\z/i
        next if payload[:sql].to_s.start_with?("BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "RELEASE", "PRAGMA")

        queries << payload[:sql]
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }

      queries
    end
  end
end

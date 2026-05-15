require "test_helper"

module Public
  class EventsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = Civic::Event.create!(
        legistar_event_id: 7621,
        body_name: "City Council",
        title: "Regular meeting",
        event_date: Date.new(2026, 5, 12)
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
      assert_includes response.body, "San Jose Civic Pulse"
      assert_includes response.body, "Regular meeting"
    end

    test "shows an event" do
      get public_event_url(@event)

      assert_response :success
      assert_includes response.body, "Regular meeting"
      assert_includes response.body, "City Council"
      assert_includes response.body, "Public Comment"
    end
  end
end

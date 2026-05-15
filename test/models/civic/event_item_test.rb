require "test_helper"

module Civic
  class EventItemTest < ActiveSupport::TestCase
    setup do
      @event = Event.create!(
        legistar_event_id: 7622,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 19)
      )
    end

    test "requires legistar_event_item_id" do
      event_item = EventItem.new(event: @event)

      assert_not event_item.valid?
      assert_includes event_item.errors[:legistar_event_item_id], "can't be blank"
    end
  end
end

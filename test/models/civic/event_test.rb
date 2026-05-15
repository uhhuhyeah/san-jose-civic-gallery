require "test_helper"

module Civic
  class EventTest < ActiveSupport::TestCase
    test "requires legistar_event_id and event_date" do
      event = Event.new

      assert_not event.valid?
      assert_includes event.errors[:legistar_event_id], "can't be blank"
      assert_includes event.errors[:event_date], "can't be blank"
    end
  end
end

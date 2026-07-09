require "test_helper"

module Civic
  class EventTest < ActiveSupport::TestCase
    test "requires source_event_id and event_date" do
      event = Event.new

      assert_not event.valid?
      assert_includes event.errors[:source_event_id], "can't be blank"
      assert_includes event.errors[:event_date], "can't be blank"
    end

    test "derives source_event_id from legistar_event_id during the transition" do
      event = Event.create!(legistar_event_id: 7777, event_date: Date.new(2026, 5, 1))
      assert_equal "7777", event.source_event_id
    end

    test "an explicitly set source_event_id is not overwritten by the legacy id" do
      event = Event.create!(
        legistar_event_id: 7778,
        source_event_id: "simbli-7778",
        event_date: Date.new(2026, 5, 1)
      )
      assert_equal "simbli-7778", event.source_event_id
    end

    test "source_event_id is unique per source_system" do
      Event.create!(legistar_event_id: 7779, event_date: Date.new(2026, 5, 1))
      duplicate = Event.new(source_event_id: "7779", event_date: Date.new(2026, 5, 1))

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:source_event_id], "has already been taken"
    end

    test "destroying an event destroys tombstone event items alongside source-present ones" do
      event = Event.create!(legistar_event_id: 99001, event_date: Date.new(2026, 5, 1))
      live_item = event.all_event_items.create!(legistar_event_item_id: 1001, title: "Live")
      tombstone = event.all_event_items.create!(
        legistar_event_item_id: 1002,
        title: "Removed upstream",
        source_present: false,
        source_missing_at: Time.current
      )

      assert_difference -> { EventItem.count }, -2 do
        event.destroy!
      end

      assert_not EventItem.exists?(live_item.id)
      assert_not EventItem.exists?(tombstone.id)
    end

    test "event_items association returns only source-present items" do
      event = Event.create!(legistar_event_id: 99002, event_date: Date.new(2026, 5, 1))
      live = event.all_event_items.create!(legistar_event_item_id: 2001, title: "Live")
      event.all_event_items.create!(
        legistar_event_item_id: 2002,
        title: "Tombstone",
        source_present: false,
        source_missing_at: Time.current
      )

      assert_equal [ live.id ], event.event_items.pluck(:id)
      assert_equal 2, event.all_event_items.count
    end

    test "listing_title avoids repeating body-only titles" do
      event = Event.new(body_name: "City Council", title: "City Council")
      assert_equal "City Council meeting", event.listing_title

      event.title = "Budget study session"
      assert_equal "Budget study session", event.listing_title
    end

    test "compute_searchable_text includes event items and linked matter data" do
      event = Event.create!(legistar_event_id: 99010, event_date: Date.new(2026, 6, 1), title: "Council meeting", body_name: "City Council")
      matter = Civic::Matter.create!(legistar_matter_id: 99011, matter_file: "26-900", title: "Budget allocation", name: "Fiscal year budget")
      event.event_items.create!(
        legistar_event_item_id: 3001,
        civic_matter_id: matter.id,
        title: "Approve budget",
        matter_file: "26-900"
      )
      # Create a second event_item without a linked matter (only denormalized matter_file)
      event.event_items.create!(
        legistar_event_item_id: 3002,
        title: "Public comment",
        matter_file: "26-901"
      )

      text = event.compute_searchable_text

      # Event's own fields
      assert_includes text, "Council meeting"
      assert_includes text, "City Council"
      # Event item titles
      assert_includes text, "Approve budget"
      assert_includes text, "Public comment"
      # Event item matter_files (denormalized)
      assert_includes text, "26-900"
      assert_includes text, "26-901"
      # Linked matter title and name (the new addition in Fix 1)
      assert_includes text, "Budget allocation"
      assert_includes text, "Fiscal year budget"
    end
  end
end

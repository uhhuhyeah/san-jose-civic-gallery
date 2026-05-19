require "test_helper"
require "rake"

class MatterThemesPreviewTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["pulse:preview"]
    @task.reenable
    ENV["SAMPLES"] = "0"
  end

  teardown do
    ENV.delete("SAMPLES")
    ENV.delete("WEEKS")
  end

  test "counts only current source agenda appearances" do
    matter = Civic::Matter.create!(legistar_matter_id: 91_001, matter_file: "26-910")
    matter.themes.create!(theme_slug: "housing")
    current_event = Civic::Event.create!(legistar_event_id: 92_001, event_date: Date.new(2026, 5, 1))
    stale_event = Civic::Event.create!(legistar_event_id: 92_002, event_date: Date.new(2026, 5, 2))
    missing_event = Civic::Event.create!(
      legistar_event_id: 92_003,
      event_date: Date.new(2026, 5, 3),
      source_present: false
    )

    current_event.event_items.create!(legistar_event_item_id: 93_001, matter:)
    current_event.all_event_items.create!(legistar_event_item_id: 93_002, matter:, source_present: false)
    stale_event.all_event_items.create!(legistar_event_item_id: 93_003, matter:, source_present: false)
    missing_event.event_items.create!(legistar_event_item_id: 93_004, matter:)

    stdout, _stderr = capture_io { @task.execute }

    assert_match(/Housing\s+1\s+1\b/, stdout)
  end
end

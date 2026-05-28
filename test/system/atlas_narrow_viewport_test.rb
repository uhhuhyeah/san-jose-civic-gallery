require "application_system_test_case"

# Renders the three primary Atlas pages (Pulse, Matter detail, Meeting detail)
# at a 375x812 viewport — the iPhone X / SE benchmark for narrow mobile.
# Each test asserts the page loads, the key Atlas chrome appears, and the
# document body does not overflow horizontally.
class AtlasNarrowViewportTest < ApplicationSystemTestCase
  NARROW_VIEWPORT = [ 375, 812 ].freeze

  setup do
    page.driver.browser.manage.window.resize_to(*NARROW_VIEWPORT)

    matter = Civic::Matter.create!(
      legistar_matter_id: 51_001,
      matter_file: "CC 26-510",
      title: "Affordable housing services agreement",
      matter_status_name: "Agenda Ready",
      matter_type_name: "Council Item",
      body_name: "City Council",
      agenda_date: Date.new(2026, 5, 19)
    )
    matter.themes.create!(theme_slug: "housing", rank: 1)

    event = Civic::Event.create!(
      legistar_event_id: 51_500,
      body_name: "City Council",
      title: "Regular meeting",
      event_date: Date.new(2026, 5, 19),
      agenda_status_name: "Final",
      minutes_status_name: "Draft"
    )
    event.event_items.create!(
      legistar_event_item_id: 51_900,
      civic_matter_id: matter.id,
      matter_id: matter.legistar_matter_id,
      agenda_sequence: 1,
      agenda_number: "1.",
      title: "Approve agreement"
    )
    event.event_items.create!(
      legistar_event_item_id: 51_901,
      agenda_sequence: 2,
      agenda_number: "(a)",
      title: "Call to Order"
    )
    event.event_items.create!(
      legistar_event_item_id: 51_902,
      agenda_sequence: 3,
      title: "How to observe the meeting"
    )

    matter.all_attachments.create!(
      legistar_matter_attachment_id: 51_001,
      name: "Memorandum",
      file_name: "memo.pdf"
    )

    @matter = matter
    @event = event
  end

  test "Pulse homepage fits within a 375px viewport" do
    visit root_path

    assert_selector "body.atlas-shell", visible: :all
    assert_selector "header.atlas-topbar"
    assert_selector ".atlas-pulse-hero h1"
    assert_no_horizontal_overflow
  end

  test "Matter detail page fits within a 375px viewport" do
    visit public_matter_path(@matter)

    assert_selector "body.atlas-shell", visible: :all
    assert_selector ".atlas-matter-header"
    assert_selector ".atlas-matter-title"
    # On narrow, the sidebar drops below the main column rather than sitting beside it.
    assert_no_horizontal_overflow
  end

  test "Meeting detail page fits within a 375px viewport" do
    visit public_event_path(@event)

    assert_selector "body.atlas-shell", visible: :all
    assert_selector ".atlas-mtg-header"
    assert_selector ".atlas-date.atlas-date--lg"
    # Substantive matters render even when the grid collapses.
    assert_selector "article.atlas-ag-matter"
    assert_no_horizontal_overflow
  end

  private

  # Capybara doesn't give us a built-in viewport-overflow check, so we measure
  # via JS: the document scrollWidth should match the viewport width. A few
  # pixels of slack covers scrollbar quirks across drivers.
  def assert_no_horizontal_overflow(slack_px: 2)
    body_width = page.evaluate_script("document.documentElement.scrollWidth")
    viewport_width = page.evaluate_script("document.documentElement.clientWidth")
    diff = body_width - viewport_width
    assert_operator diff, :<=, slack_px,
      "Page overflows horizontally: scrollWidth=#{body_width}, clientWidth=#{viewport_width}, diff=#{diff}px (slack=#{slack_px}px)"
  end
end

require "application_system_test_case"

# Renders the three primary Atlas pages (Pulse, Matter detail, Meeting detail)
# at a 375x812 viewport — the iPhone X / SE benchmark for narrow mobile.
# Each test asserts the page loads, the key Atlas chrome appears, and the
# document body does not overflow horizontally.
#
# Driver override: this class uses its own `driven_by` with screen_size set
# to the narrow viewport from boot, rather than relying on the runtime
# `resize_to` call. The resize approach passed silently in some local Chrome
# Drivers that ignored the call, which let real overflows slip through to
# CI. Booting the driver narrow guarantees the initial viewport is the one
# we want to test.
class AtlasNarrowViewportTest < ApplicationSystemTestCase
  NARROW_VIEWPORT = [ 375, 812 ].freeze
  # Allow the actual reported clientWidth to differ from 375 by this much.
  # Headless Chromium subtracts ~15px for a scrollbar in some configurations.
  VIEWPORT_SLACK_PX = 20

  # `:narrow_headless_chrome` is registered in
  # `test/application_system_test_case.rb`. It uses Chrome's mobile-device
  # emulation to force a real 375 CSS-pixel viewport even on macOS, where
  # the minimum browser-window width is otherwise ~500px.
  driven_by :narrow_headless_chrome

  setup do
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
    assert_viewport_is_narrow

    assert_selector "body.atlas-shell", visible: :all
    assert_selector "header.atlas-topbar"
    assert_selector ".atlas-pulse-hero h1"
    assert_no_horizontal_overflow
  end

  test "Matter detail page fits within a 375px viewport" do
    visit public_matter_path(@matter)
    assert_viewport_is_narrow

    assert_selector "body.atlas-shell", visible: :all
    assert_selector ".atlas-matter-header"
    assert_selector ".atlas-matter-title"
    # On narrow, the sidebar drops below the main column rather than sitting beside it.
    assert_no_horizontal_overflow
  end

  test "Meeting detail page fits within a 375px viewport" do
    visit public_event_path(@event)
    assert_viewport_is_narrow

    assert_selector "body.atlas-shell", visible: :all
    assert_selector ".atlas-mtg-header"
    assert_selector ".atlas-date.atlas-date--lg"
    # Substantive matters render even when the grid collapses.
    assert_selector "article.atlas-ag-matter"
    assert_no_horizontal_overflow
  end

  private

  # Sanity-check that the driver actually reports a narrow viewport. Without
  # this, a driver/version that silently ignores `resize_to` makes every
  # overflow assertion pass at desktop width — exactly how the original
  # version of this test went green locally while failing on CI.
  def assert_viewport_is_narrow
    actual = page.evaluate_script("document.documentElement.clientWidth")
    target = NARROW_VIEWPORT.first
    diff = (actual - target).abs
    assert_operator diff, :<=, VIEWPORT_SLACK_PX,
      "Driver viewport did not land at the narrow target: " \
      "clientWidth=#{actual}, target=#{target}, slack=#{VIEWPORT_SLACK_PX}. " \
      "If the diff is large the driver silently ignored the resize."
  end

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

require "test_helper"

class DevControllerTest < ActionDispatch::IntegrationTest
  # The Atlas test sandbox is gated to Rails.env.local? in both the route block
  # and the controller's before_action. Test env satisfies `local?`, so a normal
  # GET hits the controller.

  test "renders every Phase 1 partial under the atlas-shell body class" do
    get dev_atlas_test_path

    assert_response :success

    # The layout opts into Atlas styling through `content_for :body_class`.
    assert_select "body.atlas-shell"

    # The atlas stylesheet is loaded only on opt-in pages.
    assert_select "link[rel=stylesheet][href*=atlas]"
  end

  test "shared partials each render with their signature classes" do
    get dev_atlas_test_path

    assert_response :success

    # Topbar — brand wordmark + nav
    assert_select "header.atlas-topbar"
    assert_select "header.atlas-topbar .atlas-brand-mark"
    assert_select "header.atlas-topbar nav a", text: "Pulse"

    # Section heading pattern (used multiple times)
    assert_select ".atlas-section-head h2", minimum: 5
    assert_select ".atlas-section-head .atlas-em"
    assert_select ".atlas-section-head .atlas-rule"

    # Date plates — four sizes
    assert_select ".atlas-date.atlas-date--lg .atlas-date-day", text: "03"
    assert_select ".atlas-date.atlas-date--md"
    assert_select ".atlas-date.atlas-date--sm"
    assert_select ".atlas-date.atlas-date--xs"

    # Theme tile — all four sizes + trend variants
    assert_select "a.atlas-tile.atlas-tile--xl.atlas-tile--up"
    assert_select "a.atlas-tile.atlas-tile--l.atlas-tile--up"
    assert_select "a.atlas-tile.atlas-tile--m.atlas-tile--hot"
    assert_select "a.atlas-tile.atlas-tile--s.atlas-tile--down"

    # The XL tile carries the surfaced-matter footer
    assert_select ".atlas-tile--xl .atlas-tile-foot b", text: "Latest"

    # Body tile — name, acronym, count, label, CTA
    assert_select "a.atlas-body-tile .atlas-body-tile-name"
    assert_select "a.atlas-body-tile .atlas-body-tile-acronym", text: "T&E"
    assert_select "a.atlas-body-tile .atlas-body-tile-count", text: "14"
    assert_select "a.atlas-body-tile .atlas-body-tile-cta"

    # Summary card — label, AI pill, key points, limitations, AI note
    assert_select "section.atlas-summary"
    assert_select ".atlas-summary .atlas-summary-label"
    assert_select ".atlas-summary .atlas-ai-pill"
    assert_select ".atlas-summary h5.keys"
    assert_select ".atlas-summary h5.limits"
    assert_select ".atlas-summary .atlas-ai-note svg"

    # Facts strip
    assert_select "dl.atlas-facts-strip"
    assert_select "dl.atlas-facts-strip dt", text: "Body"
    assert_select "dl.atlas-facts-strip dd a", text: /legistar/

    # Standalone sparkline helper output
    assert_select "svg.atlas-spark path"
    assert_select "svg.atlas-spark circle"
    assert_select "svg.atlas-spark[aria-label*='Housing']"

    # Footer
    assert_select "footer.atlas-footer nav a", text: "Pulse"
  end

  test "marks the test page noindex so search engines do not pick it up" do
    get dev_atlas_test_path

    assert_match(/name="robots"[^>]*noindex/, response.body)
  end
end

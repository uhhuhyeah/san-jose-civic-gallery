require "test_helper"

class AtlasHelperTest < ActionView::TestCase
  include AtlasHelper

  test "renders a sparkline SVG for a 4-point series" do
    svg = atlas_sparkline_svg([ 4, 8, 16, 31 ])

    assert_match(/<svg[^>]*viewBox="0 0 200 40"/, svg)
    assert_match(/class="atlas-spark"/, svg)
    assert_match(/preserveAspectRatio="none"/, svg)
    assert_match(/role="img"/, svg)
    # Path "M x,y L x,y L x,y L x,y" — four coordinate pairs
    coord_count = svg.scan(/\d+\.\d+,\d+\.\d+/).size
    assert_equal 4, coord_count
    # End-of-line circle is anchored at the last point
    assert_match(/<circle [^>]*r="3"/, svg)
  end

  test "honors a custom aria label" do
    svg = atlas_sparkline_svg([ 1, 2 ], aria_label: "Housing trend")

    assert_match(/aria-label="Housing trend"/, svg)
  end

  test "uses currentColor by inheriting from CSS — no fill or stroke attributes on the path" do
    # The path element should not hard-code fill or stroke; those come from CSS
    # so trend variants on the parent tile drive the color.
    svg = atlas_sparkline_svg([ 5, 10, 15, 20 ])

    path = svg.match(/<path [^>]*>/).to_s
    assert_no_match(/fill=/, path)
    assert_no_match(/stroke=/, path)
  end

  test "centers a flat series vertically rather than dividing by zero" do
    svg = atlas_sparkline_svg([ 4, 4, 4, 4 ])

    # All four points share the same y coordinate — the line is flat at the
    # vertical midpoint of the plot area (height/2 = 20).
    coords = svg.scan(/(\d+\.\d+),(\d+\.\d+)/)
    ys = coords.map { |_, y| y.to_f }.uniq
    assert_equal 1, ys.length, "expected one unique y for a flat series, got #{ys.inspect}"
    assert_in_delta 20.0, ys.first, 0.1
  end

  test "returns nil for an empty series" do
    assert_nil atlas_sparkline_svg([])
  end

  test "returns nil for a single-point series" do
    assert_nil atlas_sparkline_svg([ 7 ])
  end

  test "handles a two-point series (minimum valid input)" do
    svg = atlas_sparkline_svg([ 3, 9 ])

    coord_count = svg.scan(/\d+\.\d+,\d+\.\d+/).size
    assert_equal 2, coord_count
  end

  test "centers a flat-at-zero series at the vertical midpoint" do
    svg = atlas_sparkline_svg([ 0, 0 ])

    ys = svg.scan(/(\d+\.\d+),(\d+\.\d+)/).map { |_, y| y.to_f }.uniq
    assert_equal 1, ys.length
    assert_in_delta 20.0, ys.first, 0.1
  end

  test "filters nil and non-finite series values rather than crashing" do
    # Stray nils or NaNs in upstream data shouldn't break the helper.
    # Filtered input below collapses to [4, 8, 16] — still valid (3 points).
    svg = atlas_sparkline_svg([ 4, nil, 8, Float::NAN, 16 ])

    refute_nil svg
    coord_count = svg.scan(/\d+\.\d+,\d+\.\d+/).size
    assert_equal 3, coord_count
  end

  test "returns nil when filtering leaves fewer than two valid points" do
    assert_nil atlas_sparkline_svg([ nil, nil ])
    assert_nil atlas_sparkline_svg([ 1, Float::INFINITY ])
  end

  # ------------------------------------------------------------------
  # atlas_trend_for — variant selection from a ThemeStat
  # ------------------------------------------------------------------

  test "atlas_trend_for: surging short-circuits everything else" do
    # Even with a lift that would otherwise map to :up, surging wins.
    assert_equal :hot, atlas_trend_for(stat(surging: true, lift: 1.2))
    assert_equal :hot, atlas_trend_for(stat(surging: true, lift: nil))
  end

  test "atlas_trend_for: lift > 2.0 -> :hot" do
    assert_equal :hot, atlas_trend_for(stat(lift: 2.1))
    assert_equal :hot, atlas_trend_for(stat(lift: 5.0))
  end

  test "atlas_trend_for: lift > 1.1 (but <= 2.0) -> :up" do
    assert_equal :up, atlas_trend_for(stat(lift: 1.11))
    assert_equal :up, atlas_trend_for(stat(lift: 1.5))
    assert_equal :up, atlas_trend_for(stat(lift: 2.0)) # exactly 2.0 is not > 2.0
  end

  test "atlas_trend_for: lift < 0.9 -> :down" do
    assert_equal :down, atlas_trend_for(stat(lift: 0.89))
    assert_equal :down, atlas_trend_for(stat(lift: 0.5))
  end

  test "atlas_trend_for: lift in [0.9, 1.1] -> :flat" do
    assert_equal :flat, atlas_trend_for(stat(lift: 1.0))
    assert_equal :flat, atlas_trend_for(stat(lift: 0.9))
    assert_equal :flat, atlas_trend_for(stat(lift: 1.1))
  end

  test "atlas_trend_for: nil lift (no prior baseline) -> :flat" do
    assert_equal :flat, atlas_trend_for(stat(lift: nil))
  end

  # ------------------------------------------------------------------
  # atlas_trend_label — pill text from a ThemeStat
  # ------------------------------------------------------------------

  test "atlas_trend_label: surging renders 'new' regardless of lift" do
    assert_equal "▲▲ new", atlas_trend_label(stat(surging: true, lift: nil))
    assert_equal "▲▲ new", atlas_trend_label(stat(surging: true, lift: 5.0))
  end

  test "atlas_trend_label: nil lift renders a bare arrow" do
    assert_equal "→", atlas_trend_label(stat(lift: nil))
  end

  test "atlas_trend_label: lift >= 2.0 prints double-up with percent" do
    # pct >= 100 -> "▲▲ N%"
    assert_equal "▲▲ 100%", atlas_trend_label(stat(lift: 2.0))
    assert_equal "▲▲ 250%", atlas_trend_label(stat(lift: 3.5))
  end

  test "atlas_trend_label: lift > 1.1 (and pct > 10) prints single-up" do
    assert_equal "▲ 50%", atlas_trend_label(stat(lift: 1.5))
    assert_equal "▲ 99%", atlas_trend_label(stat(lift: 1.99))
  end

  test "atlas_trend_label: small positive lift renders flat-arrow with + sign" do
    # pct.abs <= 10 -> "→ +N%"
    assert_equal "→ +5%", atlas_trend_label(stat(lift: 1.05))
    assert_equal "→ +10%", atlas_trend_label(stat(lift: 1.10))
  end

  test "atlas_trend_label: small negative lift renders flat-arrow without + sign" do
    # The flat band is symmetric around 0 — abs(pct) <= 10 maps to "→".
    # Negative pct keeps its '-' since it's not `.positive?`.
    assert_equal "→ -5%", atlas_trend_label(stat(lift: 0.95))
    assert_equal "→ -10%", atlas_trend_label(stat(lift: 0.90))
  end

  test "atlas_trend_label: exact-zero pct renders '→ 0%'" do
    assert_equal "→ 0%", atlas_trend_label(stat(lift: 1.0))
  end

  test "atlas_trend_label: large negative lift renders down-triangle with negative pct" do
    # Negative pct outside the flat band falls to the else branch. The '-' on
    # the percentage is intentional — pinning this prevents a future refactor
    # from silently changing the sign convention.
    assert_equal "▽ -20%", atlas_trend_label(stat(lift: 0.8))
    assert_equal "▽ -50%", atlas_trend_label(stat(lift: 0.5))
  end

  private

  # ThemeStat factory. Only `lift` and `surging` matter for trend mapping;
  # everything else is fixture noise.
  def stat(lift:, surging: false)
    Public::ThemePulse::ThemeStat.new(
      slug: "test",
      label: "Test",
      current_appearances: 4,
      prior_appearances: 2,
      current_rate: 0.1,
      prior_rate: 0.05,
      lift: lift,
      surging: surging,
      eligible: true
    )
  end
end

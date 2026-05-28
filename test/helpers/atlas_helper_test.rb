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
end

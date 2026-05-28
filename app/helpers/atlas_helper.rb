module AtlasHelper
  # Trend variant for a `Public::ThemePulse::ThemeStat`. Maps the existing
  # surging / lift values onto the four-way visual vocabulary the Atlas tiles
  # use. Returns :hot | :up | :flat | :down.
  def atlas_trend_for(stat)
    return :hot if stat.surging
    return :hot if stat.lift && stat.lift > 2.0
    return :up  if stat.lift && stat.lift > 1.1
    return :down if stat.lift && stat.lift < 0.9
    :flat
  end

  # Pill text matching a trend variant. Short on purpose — "vs last quarter"
  # context lives in the section heading, not in every pill.
  def atlas_trend_label(stat)
    return "▲▲ new" if stat.surging
    return "→"      unless stat.lift

    pct = ((stat.lift - 1) * 100).round
    if pct >= 100
      "▲▲ #{pct}%"
    elsif pct > 10
      "▲ #{pct}%"
    elsif pct.abs <= 10
      "→ #{pct.positive? ? '+' : ''}#{pct}%"
    else
      "▽ #{pct}%"
    end
  end

  # Renders an inline SVG sparkline path from a series of integers (or floats).
  # Path uses `currentColor` so the parent's CSS class (`atlas-tile--up`,
  # `atlas-tile--hot`, etc.) drives the stroke color.
  #
  # @param series [Array<Numeric>] Y-values. 4 points is the design spec but
  #   any length renders. Returns nil for blank / single-value series.
  # @param aria_label [String] accessible name on the <svg>.
  #
  # The viewBox is 200x40 with `preserveAspectRatio="none"`, so the tile's
  # CSS controls the rendered size and the path stretches to fit.
  def atlas_sparkline_svg(series, aria_label: "Quarterly trend sparkline")
    return nil if series.blank? || series.length < 2

    width = 200
    height = 40
    top_pad = 4
    bottom_pad = 4
    plot_height = height - top_pad - bottom_pad

    max = series.max
    min = series.min
    range = (max - min).to_f
    flat = range.zero?

    points = series.each_with_index.map do |value, index|
      x = (index.to_f / (series.length - 1)) * width
      normalized = flat ? 0.5 : (value - min) / range
      y = height - bottom_pad - (normalized * plot_height)
      [ x.round(2), y.round(2) ]
    end

    path_d = "M" + points.map { |x, y| "#{x},#{y}" }.join(" L")
    last_x, last_y = points.last

    content_tag(
      :svg,
      tag.path(d: path_d) + tag.circle(cx: last_x, cy: last_y, r: 3),
      class: "atlas-spark",
      viewBox: "0 0 #{width} #{height}",
      preserveAspectRatio: "none",
      role: "img",
      aria: { label: aria_label }
    )
  end
end

require "test_helper"

# Narrow-viewport Capybara driver. macOS headless Chromium imposes a ~500px
# minimum browser window width, so `screen_size: [375, 812]` alone is silently
# clamped on dev laptops while CI (Linux) honors it. Using Chrome's mobile-
# device emulation forces a real 375 CSS-pixel viewport in both environments,
# so the narrow-viewport system test fails uniformly when the layout overflows.
Capybara.register_driver :narrow_headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--disable-gpu")
  options.add_argument("--no-sandbox")
  options.add_argument("--window-size=375,812")
  options.add_emulation(
    device_metrics: { width: 375, height: 812, pixelRatio: 2.0, touch: true }
  )
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]
end

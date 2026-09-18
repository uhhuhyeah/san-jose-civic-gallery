require "application_system_test_case"
require "json"

Capybara.register_driver :webmcp_headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--disable-gpu")
  options.add_argument("--no-sandbox")
  options.add_argument("--host-resolver-rules=MAP sanjose.civicgallery.org 127.0.0.1,MAP sjusd.civicgallery.org 127.0.0.1")
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

class WebMcpTest < ApplicationSystemTestCase
  driven_by :webmcp_headless_chrome, screen_size: [ 1400, 1000 ]

  test "unsupported browsers keep normal public navigation and search working" do
    install_browser_error_capture

    visit "/"
    assert_selector "body"
    assert_no_browser_errors

    click_link "Matters", match: :first
    assert_current_path "/public/matters"
    fill_in "Search agendas, matters, and documents…", with: "housing"
    find("form.atlas-cmd").find("input").send_keys(:enter)
    assert_current_path "/public/matters", ignore_query: true
    assert_no_browser_errors
  end

  test "supported browsers discover the context tool and keep it host-scoped" do
    install_fake_webmcp

    visit "/"
    registration = wait_for_registration
    san_jose_context = page_context

    assert_equal "civicgallery_get_page_context", registration.fetch("name")
    assert_equal({ "type" => "object", "properties" => {}, "additionalProperties" => false }, registration.fetch("inputSchema"))
    assert_equal({ "readOnlyHint" => true, "untrustedContentHint" => false }, registration.fetch("annotations"))
    assert_equal true, registration.fetch("hasSignal")
    assert_equal san_jose_context, registration.fetch("result")
    assert_equal "sanjose", san_jose_context.dig("jurisdiction", "slug")

    port = Capybara.current_session.server.port
    page.driver.browser.navigate.to("http://sjusd.civicgallery.org:#{port}/")
    sjusd_registration = wait_for_registration
    sjusd_context = page_context

    assert_equal sjusd_context, sjusd_registration.fetch("result")
    assert_equal "sjusd", sjusd_context.dig("jurisdiction", "slug")
    assert_equal "simbli.sjusd", sjusd_context.dig("jurisdiction", "source_system")
    assert_not_equal san_jose_context.dig("jurisdiction", "slug"), sjusd_context.dig("jurisdiction", "slug")
  end

  private

  def install_browser_script(source)
    page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: source)
  end

  def install_browser_error_capture
    install_browser_script(<<~JAVASCRIPT)
      window.__civicGalleryWebMcpErrors = [];
      window.addEventListener("error", function (event) {
        window.__civicGalleryWebMcpErrors.push(event.message || "error");
      });
      window.addEventListener("unhandledrejection", function (event) {
        window.__civicGalleryWebMcpErrors.push(String(event.reason || "unhandled rejection"));
      });
    JAVASCRIPT
  end

  def install_fake_webmcp
    install_browser_script(<<~JAVASCRIPT)
      Object.defineProperty(document, "modelContext", {
        configurable: true,
        value: {
          registerTool: function (tool, options) {
            window.__civicGalleryWebMcpRegistration = {
              name: tool.name,
              inputSchema: tool.inputSchema,
              annotations: tool.annotations,
              hasSignal: Boolean(options && options.signal)
            };
            return Promise.resolve(tool.execute({})).then(function (result) {
              window.__civicGalleryWebMcpRegistration.result = result;
              return result;
            });
          }
        }
      });
    JAVASCRIPT
  end

  def wait_for_registration
    wait = Selenium::WebDriver::Wait.new(timeout: 5)
    wait.until do
      page.evaluate_script("window.__civicGalleryWebMcpRegistration || null")
    end
  end

  def page_context
    JSON.parse(page.evaluate_script("document.getElementById('civicgallery-webmcp-context').textContent"))
  end

  def assert_no_browser_errors
    assert_equal [], page.evaluate_script("window.__civicGalleryWebMcpErrors || []")
  end
end

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
    matter = Civic::Matter.create!(
      legistar_matter_id: 190_001,
      matter_file: "26-190",
      title: "Library outreach agreement"
    )
    install_fake_webmcp

    visit "/"
    registrations = wait_for_registration
    san_jose_context = page_context
    page_context_registration = registrations.find { |registration| registration.fetch("name") == "civicgallery_get_page_context" }
    search_registration = registrations.find { |registration| registration.fetch("name") == "search_matters" }
    detail_registration = registrations.find { |registration| registration.fetch("name") == "get_matter_detail" }

    assert_equal({ "type" => "object", "properties" => {}, "additionalProperties" => false }, page_context_registration.fetch("inputSchema"))
    assert_equal({ "readOnlyHint" => true, "untrustedContentHint" => false }, page_context_registration.fetch("annotations"))
    assert_equal true, page_context_registration.fetch("hasSignal")
    assert_equal san_jose_context, page_context_registration.fetch("result")
    assert_equal [ "query" ], search_registration.fetch("inputSchema").fetch("required")
    assert_equal 10, search_registration.fetch("inputSchema").dig("properties", "limit", "maximum")
    assert_equal [ "reference" ], detail_registration.fetch("inputSchema").fetch("required")
    assert_equal "sanjose", san_jose_context.dig("jurisdiction", "slug")
    assert_equal [ "civicgallery_get_page_context", "search_matters", "get_matter_detail" ], san_jose_context.fetch("capabilities").map { |capability| capability.fetch("name") }

    search_result = page.evaluate_async_script(<<~JAVASCRIPT)
      var done = arguments[0];
      var tool = window.__civicGalleryWebMcpTools.find(function (candidate) {
        return candidate.name === "search_matters";
      });
      tool.execute({ query: "library", limit: 1 }).then(done, function (error) {
        done({ error: error.message });
      });
    JAVASCRIPT
    assert_nil search_result["error"]
    assert_equal "civicgallery_matter_search_results", search_result.fetch("kind")
    assert_equal [ matter.matter_file ], search_result.fetch("results").pluck("matter_identifier")

    detail_result = page.evaluate_async_script(<<~JAVASCRIPT)
      var done = arguments[0];
      var reference = #{search_result.fetch("results").first.fetch("matter_reference").to_json};
      var tool = window.__civicGalleryWebMcpTools.find(function (candidate) {
        return candidate.name === "get_matter_detail";
      });
      tool.execute({ reference: reference }).then(done, function (error) {
        done({ error: error.message });
      });
    JAVASCRIPT
    assert_nil detail_result["error"]
    assert_equal "civicgallery_matter_detail", detail_result.fetch("kind")
    assert_equal matter.matter_file, detail_result.dig("matter", "matter_identifier")

    port = Capybara.current_session.server.port
    page.driver.browser.navigate.to("http://sjusd.civicgallery.org:#{port}/")
    sjusd_registrations = wait_for_registration
    sjusd_context = page_context
    sjusd_page_context_registration = sjusd_registrations.find { |registration| registration.fetch("name") == "civicgallery_get_page_context" }

    assert_equal sjusd_context, sjusd_page_context_registration.fetch("result")
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
            window.__civicGalleryWebMcpRegistrations = window.__civicGalleryWebMcpRegistrations || [];
            window.__civicGalleryWebMcpTools = window.__civicGalleryWebMcpTools || [];
            window.__civicGalleryWebMcpRegistrationResolvers = window.__civicGalleryWebMcpRegistrationResolvers || [];
            var registration = {
              name: tool.name,
              inputSchema: tool.inputSchema,
              annotations: tool.annotations,
              hasSignal: Boolean(options && options.signal)
            };
            window.__civicGalleryWebMcpRegistrations.push(registration);
            window.__civicGalleryWebMcpTools.push(tool);
            var execution = tool.name === "civicgallery_get_page_context" ?
              Promise.resolve(tool.execute({})).then(function (result) {
                registration.result = result;
              }) : Promise.resolve();
            var release = new Promise(function (resolve) {
              window.__civicGalleryWebMcpRegistrationResolvers.push(resolve);
            });
            if (window.__civicGalleryWebMcpRegistrations.length === 3) {
              window.__civicGalleryWebMcpRegistrationResolvers.forEach(function (resolve) { resolve(); });
            }
            return Promise.all([ execution, release ]);
          }
        }
      });
    JAVASCRIPT
  end

  def wait_for_registration
    wait = Selenium::WebDriver::Wait.new(timeout: 5)
    wait.until do
      registrations = page.evaluate_script("window.__civicGalleryWebMcpRegistrations || null")
      registrations if registrations && registrations.length == 3
    end
  end

  def page_context
    JSON.parse(page.evaluate_script("document.getElementById('civicgallery-webmcp-context').textContent"))
  end

  def assert_no_browser_errors
    assert_equal [], page.evaluate_script("window.__civicGalleryWebMcpErrors || []")
  end
end

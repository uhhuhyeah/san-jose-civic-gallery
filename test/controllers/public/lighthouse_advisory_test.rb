require "test_helper"
require "json"

module Public
  class LighthouseAdvisoryTest < ActionDispatch::IntegrationTest
    test "layout includes language, description, and dynamic page title" do
      get public_meetings_url

      assert_response :success
      assert_select "html[lang='en']"
      assert_select "title", "Meetings | San Jose Civic Gallery"
      assert_select "meta[name='description'][content*='Browse San Jose public meetings']"
    end

    test "homepage keeps default title and has a description" do
      get root_url

      assert_response :success
      assert_select "title", "San Jose Civic Gallery"
      assert_select "meta[name='description'][content*='civic themes the city']"
    end

    test "public get pages do not emit session cookies or csrf meta tags" do
      get root_url

      assert_response :success
      assert_nil response.headers["Set-Cookie"]
      assert_select "meta[name='csrf-token']", count: 0
      assert_select "meta[name='csrf-param']", count: 0
    end

    test "public get pages send shared-cache headers" do
      get root_url

      assert_response :success
      cache_control = response.headers["Cache-Control"]
      assert_includes cache_control, "public"
      assert_includes cache_control, "max-age=300"
      assert_includes cache_control, "s-maxage=7200"
      assert_includes cache_control, "stale-while-revalidate=60"
    end

    test "public HTML pages expose host-scoped WebMCP context" do
      get root_url

      assert_response :success
      assert_select "script#civicgallery-webmcp-context[type='application/json']", count: 1
      assert_select "script[type='module'][src*='webmcp']", count: 1

      context = JSON.parse(css_select("#civicgallery-webmcp-context").first.text)
      assert_equal "sanjose", context.dig("jurisdiction", "slug")
      assert_equal "legistar.sanjose", context.dig("jurisdiction", "source_system")
      assert_equal "pulse", context.dig("page", "kind")
      assert_equal [ "civicgallery_get_page_context" ], context.fetch("capabilities").pluck("name")
    end

    test "WebMCP context follows the SJUSD host" do
      host! "sjusd.civicgallery.org"

      get root_url

      assert_response :success
      context = JSON.parse(css_select("#civicgallery-webmcp-context").first.text)
      assert_equal "sjusd", context.dig("jurisdiction", "slug")
      assert_equal "simbli.sjusd", context.dig("jurisdiction", "source_system")
      assert_equal "Simbli (eBoardSolutions)", context.dig("jurisdiction", "source_label")
      assert_not_includes response.body, "sanjose.legistar.com"
    end

    test "non-public and non-HTML routes do not expose WebMCP context" do
      get rails_health_check_path
      assert_response :success
      assert_select "#civicgallery-webmcp-context", count: 0

      get "/jobs"
      assert_select "#civicgallery-webmcp-context", count: 0
    end

    test "context JSON safely contains a title that resembles a closing script tag" do
      event = Civic::Event.create!(
        legistar_event_id: 9002,
        title: "</script><script>window.injected = true</script>",
        body_name: "Rules Committee",
        event_date: Date.new(2026, 5, 20)
      )

      get public_event_url(event)

      assert_response :success
      assert_select "script#civicgallery-webmcp-context", count: 1
      context = JSON.parse(css_select("#civicgallery-webmcp-context").first.text)
      assert_equal "#{ERB::Util.html_escape(event.display_name)} | San Jose Civic Gallery", context.dig("page", "title")
      assert_not_includes response.body, "</script><script>window.injected"
    end

    test "detail pages use record-specific titles" do
      event = Civic::Event.create!(
        legistar_event_id: 9001,
        title: "Rules Committee",
        body_name: "Rules and Open Government Committee",
        event_date: Date.new(2026, 5, 19)
      )

      get public_event_url(event)

      assert_response :success
      assert_select "title", "Rules Committee | San Jose Civic Gallery"
      assert_select "meta[name='description'][content*='Rules Committee']"
    end
  end
end

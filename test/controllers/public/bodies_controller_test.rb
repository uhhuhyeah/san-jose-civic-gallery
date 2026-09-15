require "test_helper"

module Public
  class BodiesControllerTest < ActionDispatch::IntegrationTest
    SANJOSE_HOST = "sanjose.civicgallery.org".freeze
    SJUSD_HOST = "sjusd.civicgallery.org".freeze

    setup do
      host! SANJOSE_HOST
      @event = Civic::Event.create!(
        legistar_event_id: 7622,
        body_name: "City Council",
        title: "Regular meeting",
        event_date: Date.new(2026, 5, 19)
      )
      @matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575",
        title: "Agreement approval",
        body_name: "City Council",
        agenda_date: Date.new(2026, 5, 19)
      )
      @event.event_items.create!(
        legistar_event_item_id: 129630,
        civic_matter_id: @matter.id,
        agenda_sequence: 1,
        agenda_number: "3.4",
        title: "Approve agreement"
      )
    end

    test "shows city council meetings and matters on the San Jose host" do
      get body_path("city-council")

      assert_response :success
      assert_includes response.body, "Regular meeting"
      assert_includes response.body, "26-575"
      assert_select "a[href=?]", public_event_path(@event)
      assert_select "a[href=?]", public_matter_path(@matter)
      assert_select "a[href=?]", public_matters_path
      assert_select "a[href=?]", public_meetings_path(body_name: "City Council")
    end

    test "body pages are jurisdiction-scoped" do
      Civic::Event.create!(
        source_system: "simbli.sjusd",
        source_event_id: "sjusd:bodies:1",
        body_name: "Board of Education",
        title: "SJUSD board meeting",
        event_date: Date.new(2026, 5, 19)
      )

      host! SJUSD_HOST
      get body_path("city-council")

      assert_response :not_found

      get body_path("board-of-education")

      assert_response :success
      assert_includes response.body, "SJUSD board meeting"
      assert_not_includes response.body, "Regular meeting"

      host! SANJOSE_HOST
      get body_path("board-of-education")

      assert_response :not_found

      get body_path("city-council")

      assert_response :success
      assert_not_includes response.body, "SJUSD board meeting"
    end

    test "404s for an unresolvable body slug" do
      get body_path("no-such-body")

      assert_response :not_found

      host! SJUSD_HOST
      get body_path("no-such-body")

      assert_response :not_found
    end

    test "resolves a slug collision to the alphabetically first body name" do
      Civic::Event.create!(
        legistar_event_id: 7630,
        body_name: "Board of Education",
        title: "Plain board meeting",
        event_date: Date.new(2026, 5, 19)
      )
      Civic::Event.create!(
        legistar_event_id: 7631,
        body_name: "Board of Education.",
        title: "Dotted board meeting",
        event_date: Date.new(2026, 5, 19)
      )

      get body_path("board-of-education")

      assert_response :success
      assert_includes response.body, "Plain board meeting"
      assert_not_includes response.body, "Dotted board meeting"
    end

    test "populated body page emits a unique title, a distinct description, a canonical, and no robots meta" do
      get body_path("city-council")

      assert_response :success
      assert_select "link[rel='canonical'][href='http://#{SANJOSE_HOST}/bodies/city-council']"
      assert_select "meta[name='robots']", false
      body_title = css_select("title").text
      body_description = css_select("meta[name='description']").first["content"]
      assert_not_equal civic_jurisdictions(:sanjose).default_description, body_description

      @matter.themes.create!(theme_slug: "public_safety", rank: 1)
      get topic_path("public-safety")

      assert_response :success
      assert_not_equal body_title, css_select("title").text
    end

    test "canonical and og:url are https behind a TLS-terminating proxy" do
      get body_path("city-council"), headers: { "X-Forwarded-Proto" => "https" }

      assert_response :success
      assert_select "link[rel='canonical'][href='https://#{SANJOSE_HOST}/bodies/city-council']"
      assert_select "meta[property='og:url'][content='https://#{SANJOSE_HOST}/bodies/city-council']"
    end

    test "sends shared cache headers, no session cookie, and 304s on an ETag match" do
      get body_path("city-council")

      assert_response :success
      cache_control = response.headers["Cache-Control"]
      assert_includes cache_control, "public"
      assert_includes cache_control, "max-age=300"
      assert_includes cache_control, "s-maxage=7200"
      assert_includes cache_control, "stale-while-revalidate=60"
      assert_nil response.headers["Set-Cookie"]
      etag = response.headers["ETag"]

      get body_path("city-council"), headers: { "If-None-Match" => etag }

      assert_response :not_modified
    end

    test "bodies hub lists bodies with meeting records" do
      get bodies_path

      assert_response :success
      assert_select "a[href=?]", body_path("city-council")
      assert_select "a[href=?]", public_matters_path
      assert_select "a[href=?]", public_meetings_path
    end
  end
end

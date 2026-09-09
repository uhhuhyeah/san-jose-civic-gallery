require "test_helper"

module Public
  class YearsControllerTest < ActionDispatch::IntegrationTest
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

    test "shows records dated in the requested year for the current jurisdiction only" do
      Civic::Event.create!(
        source_system: "simbli.sjusd",
        source_event_id: "sjusd:years:1",
        body_name: "Board of Education",
        title: "SJUSD 2026 meeting",
        event_date: Date.new(2026, 6, 1)
      )

      get year_path(2026)

      assert_response :success
      assert_includes response.body, "Regular meeting"
      assert_includes response.body, "26-575"
      assert_not_includes response.body, "SJUSD 2026 meeting"
      assert_select "a[href=?]", public_event_path(@event)
      assert_select "a[href=?]", public_matter_path(@matter)
      assert_select "a[href=?]", public_matters_path

      host! SJUSD_HOST
      get year_path(2026)

      assert_response :success
      assert_includes response.body, "SJUSD 2026 meeting"
      assert_not_includes response.body, "Regular meeting"
      assert_not_includes response.body, "26-575"
    end

    test "includes matters introduced in the year even when not yet heard" do
      Civic::Matter.create!(
        legistar_matter_id: 16000,
        matter_file: "26-999",
        title: "Introduced only",
        intro_date: Date.new(2026, 7, 1)
      )

      get year_path(2026)

      assert_response :success
      assert_includes response.body, "26-999"
    end

    test "excludes records from other years" do
      Civic::Matter.create!(
        legistar_matter_id: 16001,
        matter_file: "25-100",
        title: "Older matter",
        agenda_date: Date.new(2025, 5, 19)
      )

      get year_path(2026)

      assert_response :success
      assert_not_includes response.body, "25-100"
    end

    test "a year with no records is noindex,follow with no canonical" do
      get year_path(2020)

      assert_response :success
      assert_select "meta[name='robots'][content='noindex,follow']"
      assert_select "link[rel='canonical']", false
    end

    test "non-numeric and implausible years return 404, not 500" do
      get "/years/abc"

      assert_response :not_found

      get year_path(1700)

      assert_response :not_found

      get year_path(9999)

      assert_response :not_found
    end

    test "populated year page emits a unique title, a distinct description, a canonical, and no robots meta" do
      get year_path(2026)

      assert_response :success
      assert_select "link[rel='canonical'][href='http://#{SANJOSE_HOST}/years/2026']"
      assert_select "meta[name='robots']", false
      year_title = css_select("title").text
      year_description = css_select("meta[name='description']").first["content"]
      assert_not_equal civic_jurisdictions(:sanjose).default_description, year_description

      @matter.themes.create!(theme_slug: "public_safety", rank: 1)
      get topic_path("public-safety")

      assert_response :success
      assert_not_equal year_title, css_select("title").text
    end

    test "canonical and og:url are https behind a TLS-terminating proxy" do
      get year_path(2026), headers: { "X-Forwarded-Proto" => "https" }

      assert_response :success
      assert_select "link[rel='canonical'][href='https://#{SANJOSE_HOST}/years/2026']"
      assert_select "meta[property='og:url'][content='https://#{SANJOSE_HOST}/years/2026']"
    end

    test "sends shared cache headers, no session cookie, and 304s on an ETag match" do
      get year_path(2026)

      assert_response :success
      cache_control = response.headers["Cache-Control"]
      assert_includes cache_control, "public"
      assert_includes cache_control, "max-age=300"
      assert_includes cache_control, "s-maxage=7200"
      assert_includes cache_control, "stale-while-revalidate=60"
      assert_nil response.headers["Set-Cookie"]
      etag = response.headers["ETag"]

      get year_path(2026), headers: { "If-None-Match" => etag }

      assert_response :not_modified
    end
  end
end

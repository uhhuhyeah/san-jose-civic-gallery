require "test_helper"

module Public
  class TopicsControllerTest < ActionDispatch::IntegrationTest
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
      @matter.themes.create!(theme_slug: "public_safety", rank: 2)
      @event.event_items.create!(
        legistar_event_item_id: 129630,
        civic_matter_id: @matter.id,
        agenda_sequence: 1,
        agenda_number: "3.4",
        title: "Approve agreement"
      )
    end

    test "lists public safety matters with primary-theme matters first" do
      primary = Civic::Matter.create!(
        legistar_matter_id: 16000,
        matter_file: "26-800",
        title: "Primary public safety matter"
      )
      primary.themes.create!(theme_slug: "public_safety", rank: 1)

      get topic_path("public-safety")

      assert_response :success
      assert_includes response.body, "26-800"
      assert_includes response.body, "26-575"
      assert_operator response.body.index("26-800"), :<, response.body.index("26-575")
    end

    test "excludes matters tagged with other themes" do
      transit = Civic::Matter.create!(
        legistar_matter_id: 16001,
        matter_file: "26-801",
        title: "Transit matter"
      )
      transit.themes.create!(theme_slug: "transportation", rank: 1)

      get topic_path("public-safety")

      assert_response :success
      assert_not_includes response.body, "26-801"
    end

    test "links into matters, meetings, the filtered listing, and the topics hub" do
      get topic_path("public-safety")

      assert_response :success
      assert_select "a[href=?]", public_matters_path
      assert_select "a[href=?]", public_matter_path(@matter)
      assert_select "a[href=?]", public_event_path(@event)
      assert_select "a[href=?]", public_matters_path(theme: "public_safety")
      assert_select "a[href=?]", topics_path
    end

    test "404s for a slug outside the jurisdiction vocabulary on the SJUSD host" do
      host! SJUSD_HOST

      get topic_path("public-safety")

      assert_response :not_found
    end

    test "shows SJUSD vocabulary topics on the SJUSD host only" do
      sjusd_matter = Civic::Matter.create!(
        source_system: "simbli.sjusd",
        source_matter_id: "sjusd:topics:1",
        matter_file: "SJUSD-1",
        title: "Curriculum adoption"
      )
      sjusd_matter.themes.create!(theme_slug: "curriculum_instruction", rank: 1)

      host! SJUSD_HOST
      get topic_path("curriculum-instruction")

      assert_response :success
      assert_includes response.body, "SJUSD-1"
      assert_not_includes response.body, "26-575"

      host! SANJOSE_HOST
      get topic_path("curriculum-instruction")

      assert_response :not_found
    end

    test "404s for an unknown topic slug on every host" do
      get topic_path("not-a-real-theme")

      assert_response :not_found

      host! SJUSD_HOST
      get topic_path("not-a-real-theme")

      assert_response :not_found
    end

    test "populated topic emits a unique title, a distinct description, a canonical, and no robots meta" do
      housing = Civic::Matter.create!(
        legistar_matter_id: 16002,
        matter_file: "26-900",
        title: "Housing matter"
      )
      housing.themes.create!(theme_slug: "housing", rank: 1)

      get topic_path("public-safety")

      assert_response :success
      assert_select "link[rel='canonical'][href='http://#{SANJOSE_HOST}/topics/public-safety']"
      assert_select "meta[name='robots']", false
      safety_title = css_select("title").text
      safety_description = css_select("meta[name='description']").first["content"]

      get topic_path("housing")

      assert_response :success
      housing_title = css_select("title").text
      housing_description = css_select("meta[name='description']").first["content"]

      assert_not_equal safety_title, housing_title
      assert_not_equal safety_description, housing_description
      assert_not_equal civic_jurisdictions(:sanjose).default_description, safety_description
    end

    test "a valid topic with no records is noindex,follow with no canonical" do
      get topic_path("arts-culture")

      assert_response :success
      assert_select "meta[name='robots'][content='noindex,follow']"
      assert_select "link[rel='canonical']", false
    end

    test "canonical and og:url are https behind a TLS-terminating proxy" do
      get topic_path("public-safety"), headers: { "X-Forwarded-Proto" => "https" }

      assert_response :success
      assert_select "link[rel='canonical'][href='https://#{SANJOSE_HOST}/topics/public-safety']"
      assert_select "meta[property='og:url'][content='https://#{SANJOSE_HOST}/topics/public-safety']"
    end

    test "sends shared cache headers, no session cookie, and 304s on an ETag match" do
      get topic_path("public-safety")

      assert_response :success
      cache_control = response.headers["Cache-Control"]
      assert_includes cache_control, "public"
      assert_includes cache_control, "max-age=300"
      assert_includes cache_control, "s-maxage=7200"
      assert_includes cache_control, "stale-while-revalidate=60"
      assert_nil response.headers["Set-Cookie"]
      etag = response.headers["ETag"]

      get topic_path("public-safety"), headers: { "If-None-Match" => etag }

      assert_response :not_modified
    end

    test "topics hub lists only themes with records" do
      get topics_path

      assert_response :success
      assert_select "a[href=?]", topic_path("public-safety")
      assert_select "a[href=?]", topic_path("arts-culture"), count: 0
      assert_select "a[href=?]", public_matters_path
    end

    test "topics hub is noindex when no theme has records" do
      Civic::EventItem.delete_all
      Civic::MatterTheme.delete_all
      Civic::Matter.delete_all

      get topics_path

      assert_response :success
      assert_select "meta[name='robots'][content='noindex,follow']"
      assert_select "link[rel='canonical']", false
    end
  end
end

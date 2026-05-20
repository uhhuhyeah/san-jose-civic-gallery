require "test_helper"

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

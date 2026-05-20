require "test_helper"

module Public
  class PulseControllerTest < ActionDispatch::IntegrationTest
    test "renders successfully with the Pulse section" do
      get pulse_v2_path

      assert_response :success
      assert_select "h2", "The Civic Gallery Pulse"
    end

    test "marks the page noindex so crawlers skip the WIP route" do
      get pulse_v2_path

      assert_match(/<meta name="robots" content="noindex/, response.body)
    end

    test "emits public cache headers and a conditional-GET etag" do
      get pulse_v2_path

      assert_includes response.headers["Cache-Control"], "public"
      assert response.headers["ETag"].present?
      assert_nil response.headers["Set-Cookie"]
    end

    test "shows a heating-up theme and offers the body filter" do
      matter = Civic::Matter.create!(legistar_matter_id: 99_001, matter_file: "26-991")
      matter.themes.create!(theme_slug: "housing", rank: 1)
      3.times do |i|
        event = Civic::Event.create!(
          legistar_event_id: 99_100 + i,
          event_date: Date.current - 1.week,
          body_name: "City Council"
        )
        Civic::EventItem.create!(legistar_event_item_id: 99_200 + i, civic_event_id: event.id, civic_matter_id: matter.id)
      end

      get pulse_v2_path

      assert_response :success
      assert_match(/Housing/, response.body)
      assert_select "select#pulse-body-name option", text: "City Council"
    end
  end
end

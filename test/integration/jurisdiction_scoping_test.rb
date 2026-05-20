require "test_helper"

# Exercises host-based jurisdiction scoping across the public read path: each
# host shows only its own jurisdiction's records, and records are not reachable
# from another jurisdiction's host.
class JurisdictionScopingTest < ActionDispatch::IntegrationTest
  SANJOSE_HOST = "sanjose.civicgallery.org".freeze
  SJUSD_HOST = "sjusd.civicgallery.org".freeze

  setup do
    @sanjose_event = Civic::Event.create!(
      legistar_event_id: 95_001,
      body_name: "City Council",
      title: "San Jose Council Meeting",
      event_date: Date.current
    )
    @sjusd_event = Civic::Event.create!(
      source_system: "simbli.sjusd",
      source_event_id: "sjusd-evt-1",
      body_name: "Board of Education",
      title: "SJUSD Board Meeting",
      event_date: Date.current
    )
  end

  test "meetings index on the San Jose host shows only San Jose events" do
    host! SANJOSE_HOST
    get public_meetings_url

    assert_response :success
    assert_includes response.body, "San Jose Council Meeting"
    assert_not_includes response.body, "SJUSD Board Meeting"
  end

  test "meetings index on the SJUSD host shows only SJUSD events" do
    host! SJUSD_HOST
    get public_meetings_url

    assert_response :success
    assert_includes response.body, "SJUSD Board Meeting"
    assert_not_includes response.body, "San Jose Council Meeting"
  end

  test "an event is not reachable from another jurisdiction's host" do
    host! SANJOSE_HOST
    get public_event_url(@sjusd_event)

    assert_response :not_found
  end

  test "an event is reachable from its own jurisdiction's host" do
    host! SJUSD_HOST
    get public_event_url(@sjusd_event)

    assert_response :success
    assert_includes response.body, "SJUSD Board Meeting"
  end

  test "an unknown host falls back to the default jurisdiction" do
    host! "localhost"
    get public_meetings_url

    assert_response :success
    assert_includes response.body, "San Jose Council Meeting"
    assert_not_includes response.body, "SJUSD Board Meeting"
  end
end

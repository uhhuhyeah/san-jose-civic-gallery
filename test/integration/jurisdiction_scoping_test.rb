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

  test "the homepage on the San Jose host shows city-government copy" do
    host! SANJOSE_HOST
    get root_url

    assert_response :success
    assert_includes response.body, "San Jose Civic Gallery"
    assert_includes response.body, "City Hall agenda intelligence"
    assert_includes response.body, "Citywide"
  end

  test "the homepage on the SJUSD host shows school-district copy, not city copy" do
    host! SJUSD_HOST
    get root_url

    assert_response :success
    assert_includes response.body, "San Jose Unified Civic Gallery"
    assert_includes response.body, "School board agenda intelligence"
    assert_not_includes response.body, "City Hall agenda intelligence"
    assert_not_includes response.body, "(citywide)"
  end

  test "the footer cites the San Jose source host on the San Jose host" do
    host! SANJOSE_HOST
    get public_meetings_url

    assert_includes response.body, "sanjose.legistar.com"
    assert_not_includes response.body, "simbli.eboardsolutions.com"
  end

  test "the footer cites the Simbli source host on the SJUSD host" do
    host! SJUSD_HOST
    get public_meetings_url

    assert_includes response.body, "simbli.eboardsolutions.com"
    assert_not_includes response.body, "sanjose.legistar.com"
  end
end

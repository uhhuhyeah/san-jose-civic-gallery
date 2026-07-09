require "test_helper"

module Public
  class MeetingsControllerTest < ActionDispatch::IntegrationTest
    setup do
      PublicRateLimitedSearch::RATE_LIMIT_STORE.clear
      @may_event = Civic::Event.create!(
        legistar_event_id: 7621,
        body_name: "City Council",
        title: "Regular meeting",
        event_date: Date.new(2026, 5, 12),
        agenda_status_name: "Final",
        minutes_status_name: "Draft"
      )
      @june_event = Civic::Event.create!(
        legistar_event_id: 7622,
        body_name: "Planning Commission",
        title: "Planning meeting",
        event_date: Date.new(2026, 6, 4)
      )
      matter = Civic::Matter.create!(
        legistar_matter_id: 15886,
        matter_file: "26-575",
        title: "Library outreach agreement"
      )
      @may_event.event_items.create!(
        legistar_event_item_id: 129630,
        civic_matter_id: matter.id,
        matter_id: matter.legistar_matter_id,
        agenda_sequence: 1,
        agenda_number: "3.4",
        title: "Approve library outreach agreement"
      )
      @may_event.update_searchable_text!
      matter.all_attachments.create!(legistar_matter_attachment_id: 39135, name: "Agreement")
    end

    test "lists meetings for the selected month" do
      get public_meetings_url(month: "2026-05")

      assert_response :success
      assert_includes response.body, "Meetings"
      assert_includes response.body, "May"
      assert_includes response.body, "2026"
      assert_includes response.body, "Regular meeting"
      assert_includes response.body, "City Council"
      assert_includes response.body, "Approve library outreach agreement"
      assert_includes response.body, "Final"
      assert_not_includes response.body, "Planning meeting"
    end

    test "meetings index returns 304 when client ETag matches" do
      get public_meetings_url(month: "2026-05")
      assert_response :success
      etag = response.headers["ETag"]

      get public_meetings_url(month: "2026-05"), headers: { "If-None-Match" => etag }

      assert_response :not_modified
    end

    test "lists meetings using year and month picker params" do
      get public_meetings_url(year: "2026", month_number: "6")

      assert_response :success
      assert_includes response.body, "Planning meeting"
      assert_not_includes response.body, "Regular meeting"
    end

    test "month picker preserves search and body filters" do
      get public_meetings_url(month: "2026-05", q: "library", body_name: "City Council")

      assert_response :success
      assert_includes response.body, "name=\"q\""
      assert_includes response.body, "value=\"library\""
      assert_includes response.body, "name=\"body_name\""
      assert_includes response.body, "value=\"City Council\""
    end

    test "filters meetings by body" do
      get public_meetings_url(month: "2026-06", body_name: "Planning Commission")

      assert_response :success
      assert_includes response.body, "Planning meeting"
      assert_not_includes response.body, "Regular meeting"
    end

    test "searches meeting agenda item and linked matter text" do
      get public_meetings_url(month: "2026-05", q: "library outreach")

      assert_response :success
      assert_includes response.body, "Regular meeting"
      assert_includes response.body, "3.4"
      assert_not_includes response.body, "Planning meeting"
    end

    test "shows empty state for a month without meetings" do
      get public_meetings_url(month: "2026-07")

      assert_response :success
      assert_includes response.body, "No meetings have been ingested for July 2026"
    end

    test "shows count of remaining agenda items when more than three" do
      5.times do |i|
        @may_event.event_items.create!(
          legistar_event_item_id: 200000 + i,
          agenda_sequence: 10 + i,
          agenda_number: "4.#{i}",
          title: "Additional agenda item #{i}"
        )
      end

      get public_meetings_url(month: "2026-05")

      assert_response :success
      assert_includes response.body, "+3 more agenda items"
    end

    # ---- Atlas redesign acceptance (Phase 5) ----

    test "meetings index renders the Atlas shell and the Atlas stylesheet" do
      get public_meetings_url(month: "2026-05")

      assert_response :success
      assert_select "body.atlas-shell"
      assert_select "link[rel=stylesheet][href*=atlas]"
    end

    test "meetings index renders each meeting as an atlas-meeting-row with date plate + title link" do
      get public_meetings_url(month: "2026-05")

      assert_response :success
      assert_select "article.atlas-meeting-row" do
        assert_select ".atlas-date.atlas-date--md .atlas-date-day", text: "12"
        assert_select "h2 a[href=?]", public_event_path(@may_event), text: "Regular meeting"
      end
    end

    test "month nav strip carries the search and body filters" do
      get public_meetings_url(month: "2026-05", q: "library", body_name: "City Council")

      assert_response :success
      # Previous and next links must preserve both filters so navigating
      # months keeps the user's scope.
      assert_select ".atlas-meetings-monthnav a[href=?]",
        public_meetings_path(month: "2026-04", q: "library", body_name: "City Council"),
        text: /Previous month/
      assert_select ".atlas-meetings-monthnav a[href=?]",
        public_meetings_path(month: "2026-06", q: "library", body_name: "City Council"),
        text: /Next month/
    end

    test "body-filter banner appears when a body is selected" do
      get public_meetings_url(month: "2026-06", body_name: "Planning Commission")

      assert_response :success
      assert_select ".atlas-meetings-banner strong", text: "Planning Commission"
      assert_select ".atlas-meetings-banner a.atlas-meetings-banner-clear[href=?]",
        public_meetings_path(month: "2026-06"),
        text: "View all bodies"
    end

    test "clear link appears when a filter is active and resets to the current month" do
      get public_meetings_url(month: "2026-05", q: "library")

      assert_response :success
      assert_select ".atlas-meetings-filter a.atlas-meetings-filter-clear[href=?]",
        public_meetings_path(month: "2026-05"),
        text: "Clear"
    end

    test "empty state uses the Atlas treatment when the month has no meetings" do
      get public_meetings_url(month: "2026-07")

      assert_response :success
      assert_select ".atlas-meetings-empty", text: /No meetings have been ingested for July 2026/
      assert_select "article.atlas-meeting-row", false
    end

    test "results count line shows how many meetings rendered" do
      get public_meetings_url(month: "2026-05")

      assert_response :success
      assert_select ".atlas-meetings-count strong", text: "1"
    end

    # ---- Rate limiting (P0 item 5) ----

    test "repeated meetings search requests eventually return 429" do
      PublicRateLimitedSearch::SEARCH_RATE_LIMIT.times do
        get public_meetings_url(month: "2026-05", q: "library")
        assert_response :success
      end

      get public_meetings_url(month: "2026-05", q: "library")
      assert_response :too_many_requests
    end

    test "meetings index browsing without a search query is not throttled" do
      (PublicRateLimitedSearch::SEARCH_RATE_LIMIT + 5).times do
        get public_meetings_url(month: "2026-05")
        assert_response :success
      end
    end

    test "rate-limited meetings search still returns a 304 ETag on cache hits" do
      get public_meetings_url(month: "2026-05", q: "library")
      assert_response :success
      etag = response.headers["ETag"]

      get public_meetings_url(month: "2026-05", q: "library"), headers: { "If-None-Match" => etag }
      assert_response :not_modified
    end
  end
end

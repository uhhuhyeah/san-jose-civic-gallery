require "test_helper"

module Public
  class EventsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @event = Civic::Event.create!(
        legistar_event_id: 7621,
        body_name: "City Council",
        title: "Regular meeting",
        event_date: Date.new(2026, 5, 12),
        agenda_status_name: "Final",
        minutes_status_name: "Draft"
      )

      @event.event_items.create!(
        legistar_event_item_id: 129630,
        agenda_sequence: 1,
        title: "Public Comment",
        matter_file: "CC 1.1"
      )
    end

    test "shows an event" do
      get public_event_url(@event)

      assert_response :success
      assert_includes response.body, public_meetings_path(month: "2026-05")
      assert_includes response.body, "Regular meeting"
      assert_includes response.body, "City Council"
      assert_includes response.body, "Public Comment"
    end

    test "event with no ingested agenda items is noindex'd to avoid soft 404 clustering" do
      empty_event = Civic::Event.create!(
        legistar_event_id: 7622,
        body_name: "Arts Commission",
        title: "Pending ingestion",
        event_date: Date.new(2026, 5, 18)
      )

      get public_event_url(empty_event)

      assert_response :success
      assert_select "meta[name='robots'][content='noindex,follow']"
      # The populated event in setup must stay indexable; this is the regression
      # guard for "we noindex'd too broadly" if the predicate ever drifts.
      get public_event_url(@event)
      assert_response :success
      assert_select "meta[name='robots']", false
    end

    test "event detail returns 304 when client ETag matches" do
      get public_event_url(@event)
      assert_response :success
      etag = response.headers["ETag"]

      get public_event_url(@event), headers: { "If-None-Match" => etag }

      assert_response :not_modified
    end

    test "renders matter-pending hint when item has matter_id but no synced matter" do
      @event.event_items.create!(
        legistar_event_item_id: 129631,
        agenda_sequence: 2,
        title: "Pending matter item",
        matter_id: 99999,
        matter_file: "CC 9.9"
      )

      get public_event_url(@event)

      assert_response :success
      assert_includes response.body, "Linked matter sync pending"
      assert_includes response.body, "CC 9.9"
    end

    test "eager-loads items, matters, and attachments" do
      matter_a = Civic::Matter.create!(legistar_matter_id: 18001, matter_file: "26-A")
      matter_b = Civic::Matter.create!(legistar_matter_id: 18002, matter_file: "26-B")
      matter_c = Civic::Matter.create!(legistar_matter_id: 18003, matter_file: "26-C")

      [ matter_a, matter_b, matter_c ].each_with_index do |matter, i|
        @event.event_items.create!(
          legistar_event_item_id: 200_000 + i,
          agenda_sequence: 10 + i,
          title: "Item #{i}",
          civic_matter_id: matter.id,
          matter_id: matter.legistar_matter_id
        )
        matter.all_attachments.create!(legistar_matter_attachment_id: 300_000 + i, name: "Att #{i}")
      end

      queries = count_app_queries { get public_event_url(@event) }

      assert_response :success
      assert_operator queries.size, :<=, 19,
        "Expected events#show to issue at most 19 SQL queries (5 eager-load incl. matter themes + 8 cache-version + 1 event-summary load + 2 jurisdiction resolution + 3 Atlas: previous + next adjacent meeting + body meeting count); got #{queries.size}:\n#{queries.join("\n")}"
    end

    # ---- Atlas redesign acceptance (Phase 4) ----

    test "meeting page renders the Atlas shell and the Atlas stylesheet" do
      get public_event_url(@event)

      assert_response :success
      assert_select "body.atlas-shell"
      assert_select "link[rel=stylesheet][href*=atlas]"
    end

    test "meeting header includes a date plate with day-of-week" do
      get public_event_url(@event)

      assert_response :success
      assert_select ".atlas-mtg-header .atlas-date.atlas-date--lg .atlas-date-dow", text: "Tuesday"
      assert_select ".atlas-mtg-header .atlas-date.atlas-date--lg .atlas-date-day", text: "12"
    end

    test "substantive agenda items render as nested matter rows, sectioned procedural rows as headings" do
      # (a) Call to order — section marker
      @event.event_items.create!(
        legistar_event_item_id: 401_001,
        agenda_sequence: 3,
        agenda_number: "(a)",
        title: "Call to Order"
      )
      # (d) Reports to Committee — section marker
      @event.event_items.create!(
        legistar_event_item_id: 401_002,
        agenda_sequence: 4,
        agenda_number: "(d)",
        title: "Reports to Committee"
      )
      matter = Civic::Matter.create!(legistar_matter_id: 401_500, matter_file: "CC 26-401", title: "Substantive matter on agenda")
      matter.themes.create!(theme_slug: "housing", rank: 1)
      @event.event_items.create!(
        legistar_event_item_id: 401_003,
        agenda_sequence: 5,
        agenda_number: "1.",
        civic_matter_id: matter.id,
        matter_id: matter.legistar_matter_id,
        title: "First report"
      )

      get public_event_url(@event)

      assert_response :success
      assert_select ".atlas-ag-section .atlas-ag-marker", text: "(a)"
      assert_select ".atlas-ag-section .atlas-ag-marker", text: "(d)"
      assert_select ".atlas-ag-section h3", text: "Call to Order"
      # Substantive matter row carries the matter code chip + theme tag + link
      assert_select "article.atlas-ag-matter .atlas-ag-item-code", text: "CC 26-401"
      assert_select "article.atlas-ag-matter h4 a[href=?]", public_matter_path(matter)
      assert_select "article.atlas-ag-matter .atlas-ag-item-theme", text: "Housing"
    end

    test "notice-tier items are grouped into the folded 'How to watch & participate' panel" do
      get public_event_url(@event)

      assert_response :success
      # Existing fixture has one notice-shaped item ("Public Comment" with no
      # civic_matter_id and no section marker)
      assert_select ".atlas-notices" do
        assert_select "h3 .atlas-em", text: "watch & participate"
        assert_select "details.atlas-notice", minimum: 1
      end
    end

    test "adjacent meetings sidebar shows previous and next meetings of the same body" do
      previous = Civic::Event.create!(
        legistar_event_id: 7600,
        body_name: "City Council",
        event_date: Date.new(2026, 4, 28),
        title: "Earlier meeting"
      )
      following = Civic::Event.create!(
        legistar_event_id: 7700,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 26),
        title: "Later meeting"
      )
      _other_body = Civic::Event.create!(
        legistar_event_id: 7650,
        body_name: "Planning Commission",
        event_date: Date.new(2026, 5, 13),
        title: "Different body"
      )

      get public_event_url(@event)

      assert_response :success
      assert_select ".atlas-rail-card h4", text: "Adjacent meetings"
      assert_select ".atlas-rail-sibling[href=?]", public_event_path(previous)
      assert_select ".atlas-rail-sibling[href=?]", public_event_path(following)
      # Other-body meetings are not listed as siblings
      assert_select ".atlas-rail-sibling[href=?]", public_event_path(_other_body), count: 0
    end

    test "themes-on-agenda sidebar lists primary themes from substantive items" do
      housing = Civic::Matter.create!(legistar_matter_id: 410_001, matter_file: "26-A")
      housing.themes.create!(theme_slug: "housing", rank: 1)
      transit = Civic::Matter.create!(legistar_matter_id: 410_002, matter_file: "26-B")
      transit.themes.create!(theme_slug: "transportation", rank: 1)
      [ housing, transit ].each_with_index do |m, i|
        @event.event_items.create!(
          legistar_event_item_id: 410_100 + i,
          agenda_sequence: 10 + i,
          agenda_number: "#{i + 1}.",
          civic_matter_id: m.id,
          matter_id: m.legistar_matter_id,
          title: m.matter_file
        )
      end

      get public_event_url(@event)

      assert_response :success
      assert_select ".atlas-rail-card h4", text: "Themes on this agenda"
      assert_select ".atlas-rail-themes a[href=?]", public_matters_path(theme: "housing"), text: /Housing/
      assert_select ".atlas-rail-themes a[href=?]", public_matters_path(theme: "transportation"), text: /Transportation/
    end

    test "body tile renders with the body name and meeting count for that body" do
      Civic::Event.create!(legistar_event_id: 7510, body_name: "City Council", event_date: Date.new(2026, 4, 1))

      get public_event_url(@event)

      assert_response :success
      assert_select "a.atlas-body-tile[href=?]", public_meetings_path(body_name: "City Council")
      assert_select "a.atlas-body-tile .atlas-body-tile-name", text: "City Council"
      # Two events with body_name "City Council" — the test fixture + the seed above
      assert_select "a.atlas-body-tile .atlas-body-tile-count", text: "2"
    end

    private

    def count_app_queries
      queries = []
      callback = lambda do |_name, _start, _finish, _id, payload|
        next if payload[:name].to_s =~ /\A(SCHEMA|TRANSACTION|EXPLAIN)\z/i
        next if payload[:sql].to_s.start_with?("BEGIN", "COMMIT", "ROLLBACK", "SAVEPOINT", "RELEASE", "PRAGMA")

        queries << payload[:sql]
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }

      queries
    end
  end
end

require "test_helper"

module Public
  class PulseControllerTest < ActionDispatch::IntegrationTest
    test "renders the homepage as an Atlas-shelled page with the Pulse section" do
      get root_path

      assert_response :success
      assert_select "body.atlas-shell"
      assert_select "link[rel=stylesheet][href*=atlas]"
      assert_select ".atlas-section-head h2 .atlas-em", text: "Pulse"
    end

    test "is indexable (no robots noindex on the homepage)" do
      get root_path

      assert_no_match(/name="robots"[^>]*noindex/, response.body)
    end

    test "emits public cache headers and a conditional-GET etag" do
      get root_path

      assert_includes response.headers["Cache-Control"], "public"
      assert response.headers["ETag"].present?
      assert_nil response.headers["Set-Cookie"]
    end

    test "conditional homepage request avoids aggregate table probes" do
      get root_path
      etag = response.headers.fetch("ETag")
      sql_queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _started, _finished, _unique_id, payload|
        sql_queries << payload[:sql]
      end

      begin
        get root_path, headers: { "If-None-Match" => etag }
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      assert_response :not_modified
      assert_not sql_queries.any? { |sql| sql.include?("generated_artifacts") }
      assert_not sql_queries.any? { |sql| sql.include?("document_extracted_texts") }
      assert_not sql_queries.any? { |sql| sql.include?("civic_matter_themes") }
    end

    test "the legacy /pulse-v2 path permanently redirects to root" do
      get "/pulse-v2"

      assert_response :moved_permanently
      assert_redirected_to "/"
    end

    test "atlas tiles link to theme-filtered matters pages when there is activity" do
      # Seed at least one substantive appearance so the Atlas renders tiles
      # rather than the empty-state card.
      matter = Civic::Matter.create!(legistar_matter_id: 30_001, matter_file: "26-300")
      matter.themes.create!(theme_slug: "housing", rank: 1)
      event = Civic::Event.create!(legistar_event_id: 30_100, event_date: Date.current - 1.week, body_name: "City Council")
      Civic::EventItem.create!(legistar_event_item_id: 30_200, civic_event_id: event.id, civic_matter_id: matter.id)

      get root_path

      assert_response :success
      # Every theme in the taxonomy gets a tile, regardless of count
      assert_select ".atlas-pulse-grid a.atlas-tile[href=?]", public_matters_path(theme: "housing")
      assert_select ".atlas-pulse-grid a.atlas-tile[href=?]", public_matters_path(theme: "transportation")
      # Atlas legend renders when tiles do
      assert_select ".atlas-pulse-legend"
    end

    test "falls back to the empty-state card when no theme has activity yet" do
      get root_path

      assert_response :success
      assert_select ".atlas-empty-state h3", text: "Not enough activity yet"
      assert_select ".atlas-pulse-grid", false
    end

    test "surfaces recent decisions with their generated summary in the 'In session' rail" do
      matter = Civic::Matter.create!(
        legistar_matter_id: 42_001,
        matter_file: "26-700",
        title: "Affordable housing agreement",
        body_name: "City Council",
        agenda_date: Date.current
      )
      matter.themes.create!(theme_slug: "housing", rank: 1)
      attachment = matter.all_attachments.create!(legistar_matter_attachment_id: 42_100, name: "Staff report")
      extracted = attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Body text",
        character_count: 9
      )
      attachment.generated_artifacts.create!(
        source_artifact: extracted,
        kind: Generated::SummarizeMatterAttachment::KIND,
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
        input_sha256: "decision-1",
        content: { "summary" => "Authorizes a $2.4M affordable-housing services contract.", "document_status" => "final" }
      )

      get root_path

      assert_response :success
      assert_select ".atlas-session-list"
      assert_select ".atlas-section-head h2 .atlas-em", text: "session"
      assert_includes response.body, "26-700"
      assert_includes response.body, "Authorizes a $2.4M affordable-housing services contract."
      assert_select "a[href=?]", public_matter_path(matter)
    end

    test "omits the In session rail when no matter has a summary" do
      matter = Civic::Matter.create!(legistar_matter_id: 42_002, matter_file: "26-701", agenda_date: Date.current)
      matter.all_attachments.create!(legistar_matter_attachment_id: 42_101, name: "Unsummarized report")

      get root_path

      assert_response :success
      assert_select ".atlas-session-list", false
    end

    test "shows a heating-up theme card and offers the body filter" do
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

      get root_path

      assert_response :success
      assert_match(/Housing/, response.body)
      assert_select ".atlas-heat-rail .atlas-heat-card h3", text: "Housing"
      assert_select "select#pulse-body-name option", text: "City Council"
    end

    test "ledger reports the four headline stats with 'matters heard' replacing 'agenda items'" do
      get root_path

      assert_response :success
      assert_select ".atlas-pulse-ledger .atlas-pulse-ledger-cell span", text: "Meetings ingested"
      assert_select ".atlas-pulse-ledger .atlas-pulse-ledger-cell span", text: "Matters heard"
      assert_select ".atlas-pulse-ledger .atlas-pulse-ledger-cell span", text: "Distinct matters"
      assert_select ".atlas-pulse-ledger .atlas-pulse-ledger-cell span", text: "Document extractions"
      # The 'agenda items' headline from the pre-Atlas design no longer appears.
      assert_select ".atlas-pulse-ledger .atlas-pulse-ledger-cell span", text: "Agenda items", count: 0
    end

    test "matters_heard counts substantive event items, not total agenda rows" do
      matter = Civic::Matter.create!(legistar_matter_id: 60_001, matter_file: "26-600")
      event = Civic::Event.create!(legistar_event_id: 60_100, event_date: Date.current - 1.week, body_name: "City Council")
      # Two substantive items (with civic_matter_id) and one procedural (no matter)
      Civic::EventItem.create!(legistar_event_item_id: 60_201, civic_event_id: event.id, civic_matter_id: matter.id)
      Civic::EventItem.create!(legistar_event_item_id: 60_202, civic_event_id: event.id, civic_matter_id: matter.id)
      Civic::EventItem.create!(legistar_event_item_id: 60_203, civic_event_id: event.id, civic_matter_id: nil, title: "Call to Order")

      get root_path

      assert_response :success
      # Find the "Matters heard" cell and its strong value
      assert_select ".atlas-pulse-ledger .atlas-pulse-ledger-cell" do
        assert_select "span", text: "Matters heard"
      end
      # The strong value should be 2, not 3 — procedural items are excluded
      assert_select ".atlas-pulse-ledger .atlas-pulse-ledger-cell strong", text: "2"
    end
  end
end

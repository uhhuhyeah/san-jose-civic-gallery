require "test_helper"

module Public
  class PulseControllerTest < ActionDispatch::IntegrationTest
    test "renders the homepage with the Pulse section" do
      get root_path

      assert_response :success
      assert_select "h2", "The Civic Gallery Pulse"
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

    test "renders the browse-by-topic bar linking to theme filters" do
      get root_path

      assert_response :success
      assert_select "nav.topic-bar a.pill[href=?]", public_matters_path(theme: "housing"), text: "Housing"
      assert_select "nav.topic-bar a.pill[href=?]", public_matters_path(theme: "transportation"), text: "Transportation"
    end

    test "surfaces recent decisions with their generated summary" do
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
      assert_includes response.body, "What's being decided"
      assert_includes response.body, "26-700"
      assert_includes response.body, "Authorizes a $2.4M affordable-housing services contract."
      assert_select "a[href=?]", public_matter_path(matter)
    end

    test "omits the recent-decisions module when no matter has a summary" do
      matter = Civic::Matter.create!(legistar_matter_id: 42_002, matter_file: "26-701", agenda_date: Date.current)
      matter.all_attachments.create!(legistar_matter_attachment_id: 42_101, name: "Unsummarized report")

      get root_path

      assert_response :success
      assert_not_includes response.body, "What's being decided"
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

      get root_path

      assert_response :success
      assert_match(/Housing/, response.body)
      assert_select "select#pulse-body-name option", text: "City Council"
    end
  end
end

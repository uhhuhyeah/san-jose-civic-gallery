require "test_helper"

module Public
  class MattersControllerTest < ActionDispatch::IntegrationTest
    setup do
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
        matter_status_name: "Agenda Ready",
        matter_type_name: "Council Item",
        body_name: "City Council",
        requester: "City Manager",
        agenda_date: Date.new(2026, 5, 19),
        last_synced_at: Time.zone.parse("2026-05-15 10:00:00")
      )
      @event.event_items.create!(
        legistar_event_item_id: 129630,
        civic_matter_id: @matter.id,
        matter_id: @matter.legistar_matter_id,
        agenda_sequence: 1,
        agenda_number: "3.4",
        title: "Approve agreement"
      )
      @attachment = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 39135,
        name: "Agreement PDF",
        hyperlink: "https://sanjose.legistar.com/View.ashx?M=F&ID=1",
        file_name: "agreement.pdf",
        source_file_checksum_sha256: "abc123def456"
      )
    end

    test "gets index" do
      get public_matters_url

      assert_response :success
      assert_includes response.body, "Matters"
      assert_includes response.body, "26-575"
      assert_includes response.body, "Agreement approval"
    end

    test "filters matters by query" do
      Civic::Matter.create!(
        legistar_matter_id: 15887,
        matter_file: "26-999",
        title: "Unrelated zoning item"
      )

      get public_matters_url(q: "26-575")

      assert_response :success
      assert_includes response.body, "26-575"
      assert_not_includes response.body, "26-999"
    end

    test "filters matters by theme with primary-theme matters first" do
      @matter.themes.create!(theme_slug: "housing", rank: 2)
      primary = Civic::Matter.create!(legistar_matter_id: 16000, matter_file: "26-800", title: "Primary housing matter")
      primary.themes.create!(theme_slug: "housing", rank: 1)
      transit = Civic::Matter.create!(legistar_matter_id: 16001, matter_file: "26-801", title: "Transit matter")
      transit.themes.create!(theme_slug: "transportation", rank: 1)

      get public_matters_url(theme: "housing")

      assert_response :success
      assert_includes response.body, "Housing"
      assert_includes response.body, "26-800"
      assert_includes response.body, "26-575"
      assert_not_includes response.body, "26-801"
      assert_operator response.body.index("26-800"), :<, response.body.index("26-575")
    end

    test "ignores an unknown theme slug" do
      get public_matters_url(theme: "not_a_theme")

      assert_response :success
      assert_includes response.body, "26-575"
    end

    test "shows the primary theme as a pill linking to the theme filter" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      get public_matter_url(@matter)

      assert_response :success
      assert_select "a.pill[href=?]", public_matters_path(theme: "housing"), text: "Housing"
    end

    test "shows a primary theme pill on each matter row in the index" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      get public_matters_url

      assert_response :success
      assert_select ".record-row a.pill[href=?]", public_matters_path(theme: "housing"), text: "Housing"
    end

    test "finds matters by successful extracted document text" do
      other = Civic::Matter.create!(
        legistar_matter_id: 15887,
        matter_file: "26-999",
        title: "Unrelated zoning item"
      )
      other.all_attachments.create!(
        legistar_matter_attachment_id: 39136,
        name: "Zoning memo"
      ).extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "This document mentions airport noise only.",
        character_count: 42
      )
      @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "This staff report describes library outreach funding.",
        character_count: 52
      )

      get public_matters_url(q: "library outreach")

      assert_response :success
      assert_includes response.body, "26-575"
      assert_includes response.body, "Extracted document text matches"
      assert_includes response.body, "Agreement PDF"
      assert_includes response.body, "library"
      assert_not_includes response.body, "26-999"
    end

    test "excludes document matches from attachments no longer present in source" do
      archived = @matter.all_attachments.create!(
        legistar_matter_attachment_id: 39137,
        name: "Archived attachment",
        source_present: false
      )
      archived.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Archived material mentioning library outreach.",
        character_count: 46
      )

      get public_matters_url(q: "library outreach")

      assert_response :success
      assert_not_includes response.body, "Archived attachment"
      assert_not_includes response.body, "Extracted document text matches"
    end

    test "escapes html in extracted document snippets" do
      @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Notes mentioning <script>alert(1)</script> library outreach funding.",
        character_count: 68
      )

      get public_matters_url(q: "library outreach")

      assert_response :success
      assert_not_includes response.body, "<script>alert(1)</script>"
    end

    test "shows matter with related meetings and attachment status" do
      @attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 fake"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )
      extracted_text = @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "This agreement authorizes a city service contract.",
        character_count: 51,
        extracted_at: Time.current
      )
      @attachment.generated_artifacts.create!(
        source_artifact: extracted_text,
        kind: Generated::SummarizeMatterAttachment::KIND,
        status: "succeeded",
        model_identifier: "gpt-4o-mini",
        prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
        input_sha256: "abc123",
        content: {
          "summary" => "This appears to be a draft agreement summary.",
          "key_points" => [ "Authorizes a city service contract." ],
          "limitations" => [ "Generated from extracted text." ],
          "document_status" => "draft"
        }
      )

      get public_matter_url(@matter)

      assert_response :success
      assert_includes response.body, "Official Matter"
      assert_includes response.body, "26-575"
      assert_includes response.body, "Regular meeting"
      assert_includes response.body, "Agreement PDF"
      assert_includes response.body, "File imported"
      assert_includes response.body, "Extracted Text Preview"
      assert_includes response.body, "This agreement authorizes"
      assert_includes response.body, "Generated Summary"
      assert_includes response.body, "Generated summary available"
      assert_includes response.body, "This appears to be a draft agreement summary."
      assert_includes response.body, "The source text indicates this attachment appears to be a draft document."
      assert_includes response.body, "Review the official source document before relying on this summary."
      assert_not_includes response.body, "poisoned PDF"
      assert_not_includes response.body, "Rails auto-escapes"
      assert_includes response.body, "Open source document"
    end

    test "matter detail returns 304 when client ETag matches" do
      get public_matter_url(@matter)
      assert_response :success
      etag = response.headers["ETag"]

      get public_matter_url(@matter), headers: { "If-None-Match" => etag }

      assert_response :not_modified
    end

    test "shows generated summary pending when extracted text exists without a summary" do
      @attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 fake"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )
      @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "This agreement authorizes a city service contract.",
        character_count: 51
      )

      get public_matter_url(@matter)

      assert_response :success
      assert_includes response.body, "Generated summary pending"
      assert_includes response.body, "This attachment has extracted text, but a generated summary has not been added yet."
    end

    test "shows generated summary unavailable reason when source file is not imported" do
      get public_matter_url(@matter)

      assert_response :success
      assert_includes response.body, "Generated summary not available"
      assert_includes response.body, "The source file has not been imported yet."
    end

    test "explains unavailable official source link when imported file has no public URL" do
      @attachment.update!(hyperlink: nil)
      @attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 fake"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )

      get public_matter_url(@matter)

      assert_response :success
      assert_includes response.body, "Official source link"
      assert_includes response.body, "Official source link unavailable"
      assert_includes response.body, "The file was imported, but the current source metadata does not include a public document URL."
      assert_not_includes response.body, "No official document link recorded"
    end

    test "shows a fallback note when a succeeded summary has blank summary text" do
      @attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 fake"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )
      extracted_text = @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "This agreement authorizes a city service contract.",
        character_count: 51
      )
      @attachment.generated_artifacts.create!(
        source_artifact: extracted_text,
        kind: Generated::SummarizeMatterAttachment::KIND,
        status: "succeeded",
        model_identifier: "gpt-4o-mini",
        prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
        input_sha256: "blank-summary",
        content: {
          "summary" => "",
          "key_points" => [],
          "limitations" => [],
          "document_status" => "unknown"
        }
      )

      get public_matter_url(@matter)

      assert_response :success
      assert_includes response.body, "The model returned an empty summary; review the official source document."
    end

    test "shows sanjoseca.gov attachment hyperlinks as official source documents" do
      @attachment.update!(
        hyperlink: "https://www.sanjoseca.gov/your-government/appointees/city-clerk/language-access-for-city-council-and-council-committee-meetings",
        file_name: ""
      )

      get public_matter_url(@matter)

      assert_response :success
      assert_includes response.body, "Open source document"
      assert_not_includes response.body, "Official source link unavailable"
    end
  end
end

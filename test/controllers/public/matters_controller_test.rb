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

    test "shows matter with related meetings and attachment status" do
      @attachment.source_file.attach(
        io: StringIO.new("%PDF-1.4 fake"),
        filename: "agreement.pdf",
        content_type: "application/pdf"
      )
      @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "This agreement authorizes a city service contract.",
        character_count: 51,
        extracted_at: Time.current
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
      assert_includes response.body, "Open source document"
    end

    test "shows sanjoseca.gov attachment hyperlinks as official source documents" do
      @attachment.update!(
        hyperlink: "https://www.sanjoseca.gov/your-government/appointees/city-clerk/language-access-for-city-council-and-council-committee-meetings",
        file_name: ""
      )

      get public_matter_url(@matter)

      assert_response :success
      assert_includes response.body, "Open source document"
      assert_not_includes response.body, "No official document link recorded"
    end
  end
end

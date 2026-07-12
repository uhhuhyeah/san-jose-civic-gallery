require "test_helper"

module Public
  class DataControllerTest < ActionDispatch::IntegrationTest
    test "renders the empty-state when nothing has been ingested" do
      get data_url

      assert_response :success
      assert_includes response.body, "Data Health"
      assert_includes response.body, "No data ingested yet"
    end

    test "renders all sections when data exists" do
      matter = Civic::Matter.create!(
        legistar_matter_id: 1,
        matter_file: "26-001",
        agenda_date: Date.new(2026, 5, 19),
        last_synced_at: 2.hours.ago
      )
      Civic::Event.create!(
        legistar_event_id: 1,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 19),
        last_synced_at: 2.hours.ago
      )
      processed = matter.all_attachments.create!(
        legistar_matter_attachment_id: 1,
        name: "Agreement",
        hyperlink: "https://sanjose.legistar.com/View.ashx?ID=1",
        last_synced_at: 2.hours.ago
      )
      processed.source_file.attach(io: StringIO.new("%PDF-1.4 fake"), filename: "a.pdf", content_type: "application/pdf")
      processed.extracted_texts.create!(extractor_name: "pdftotext", status: "ok", content: "Body text", character_count: 9)
      processed.generated_artifacts.create!(
        kind: Generated::SummarizeMatterAttachment::KIND,
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
        input_sha256: "abc",
        content: { "summary" => "ok" }
      )
      # Three additional eligible-but-unprocessed attachments so the
      # shared-denominator rates show a low percentage instead of 100%.
      3.times do |i|
        matter.all_attachments.create!(
          legistar_matter_attachment_id: 100 + i,
          name: "Pending #{i}",
          hyperlink: "https://sanjose.legistar.com/View.ashx?ID=#{100 + i}"
        )
      end

      get data_url

      assert_response :success
      # New Atlas section headings (em-flourish wraps the second word)
      assert_select ".atlas-section-head h2 .atlas-em", text: "we have"
      assert_select ".atlas-section-head h2 .atlas-em", text: "fresh"
      assert_select ".atlas-section-head h2 .atlas-em", text: "reliable"
      assert_select ".atlas-section-head h2 .atlas-em", text: "fell out"
      assert_includes response.body, "About this page"
      # New label and shared denominator (1 processed of 4 eligible = 25%).
      assert_includes response.body, "Attachments with imported source files"
      assert_includes response.body, "Attachments with AI summaries"
      assert_includes response.body, "25%"
      assert_includes response.body, "(1 / 4)"
      # Source label uses the platform name, not the internal source_system identifier.
      assert_includes response.body, "Source: Legistar"
      assert_not_includes response.body, "legistar.sanjose"
      # All three Legistar hosts surfaced in the About section for verifiability.
      assert_includes response.body, "webapi.legistar.com/v1/sanjose"
      assert_includes response.body, "sanjose.legistar.com"
      assert_includes response.body, "legistar.granicus.com"
      # Most recent matter surfaced
      assert_includes response.body, "26-001"
    end

    test "names Simbli, not Legistar, as the source on the SJUSD host" do
      host! "sjusd.civicgallery.org"
      # A synced record so the freshness banner (with the Source label) renders.
      Civic::Event.create!(
        source_system: "simbli.sjusd",
        source_event_id: "sjusd:evt-1",
        body_name: "Board of Education",
        event_date: Date.current,
        last_synced_at: 2.hours.ago
      )

      get data_url

      assert_response :success
      # Lead paragraph, freshness banner, and About block all name Simbli.
      assert_includes response.body, "ingested from Simbli (eBoardSolutions)"
      assert_includes response.body, "Source: Simbli (eBoardSolutions)"
      assert_includes response.body, "simbli.eboardsolutions.com"
      # Nothing on the district host should read as Legistar.
      assert_not_includes response.body, "Legistar"
      assert_not_includes response.body, "webapi.legistar.com/v1/sanjose"
    end

    test "names IQM2, not Legistar, as the source on the Santa Clara County host" do
      host! "santaclaracounty.civicgallery.org"
      # A synced record so the freshness banner (with the Source label) renders.
      Civic::Event.create!(
        source_system: "iqm2.sccgov",
        source_event_id: "17599",
        body_name: "Board of Supervisors",
        event_date: Date.current,
        last_synced_at: 2.hours.ago
      )

      get data_url

      assert_response :success
      # Lead paragraph, freshness banner, and About block all name IQM2.
      assert_includes response.body, "ingested from IQM2 (Granicus)"
      assert_includes response.body, "Source: IQM2 (Granicus)"
      assert_includes response.body, "sccgov.iqm2.com"
      # Nothing on the county host should read as Legistar.
      assert_not_includes response.body, "Legistar"
      assert_not_includes response.body, "webapi.legistar.com/v1/sanjose"
    end

    test "returns 304 when client ETag matches" do
      Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001", last_synced_at: 2.hours.ago)

      get data_url
      assert_response :success
      etag = response.headers["ETag"]
      assert etag.present?, "expected ETag header on response"

      get data_url, headers: { "If-None-Match" => etag }
      assert_response :not_modified
    end

    test "footer link to data page is present on other pages" do
      get public_matters_url

      assert_response :success
      assert_includes response.body, "Data Health"
      assert_includes response.body, data_path
      assert_includes response.body, public_meetings_path
    end

    test "data page renders inside the Atlas shell" do
      get data_url

      assert_response :success
      assert_select "body.atlas-shell"
      assert_select "link[rel=stylesheet][href*=atlas]"
      assert_select "header.atlas-data-header h1", text: "Data Health"
    end

    test "freshness banner status variant reflects the snapshot freshness level" do
      Civic::Event.create!(legistar_event_id: 1, body_name: "City Council", event_date: Date.current, last_synced_at: 2.hours.ago)

      get data_url

      assert_response :success
      assert_select "section.atlas-data-freshness"
      assert_select ".atlas-data-freshness-dot"
    end

    test "rate meters render with progressbar role and percentage labels" do
      matter = Civic::Matter.create!(legistar_matter_id: 1, matter_file: "26-001", last_synced_at: 2.hours.ago)
      3.times do |i|
        matter.all_attachments.create!(
          legistar_matter_attachment_id: 100 + i,
          name: "Pending #{i}",
          hyperlink: "https://sanjose.legistar.com/View.ashx?ID=#{100 + i}"
        )
      end

      get data_url

      assert_response :success
      assert_select ".atlas-data-rate[role=group]", minimum: 5
      assert_select ".atlas-data-rate-bar[role=progressbar]"
    end
  end
end

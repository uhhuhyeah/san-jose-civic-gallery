require "digest"
require "test_helper"

module Public
  class MattersControllerTest < ActionDispatch::IntegrationTest
    setup do
      PublicRateLimitedSearch::RATE_LIMIT_STORE.clear
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

    test "filters by the SJUSD vocabulary on the SJUSD host" do
      host! "sjusd.civicgallery.org"
      matter = Civic::Matter.create!(
        source_system: "simbli.sjusd",
        source_matter_id: "sjusd:1:1",
        matter_file: "SJUSD-1-1",
        title: "Special education services agreement"
      )
      matter.themes.create!(theme_slug: "special_education", rank: 1)

      get public_matters_url(theme: "special_education")

      assert_response :success
      assert_includes response.body, "Special Education"
      assert_includes response.body, "SJUSD-1-1"
    end

    test "treats a city-only theme slug as unknown on the SJUSD host" do
      host! "sjusd.civicgallery.org"

      get public_matters_url(theme: "housing")

      assert_response :success
      assert_not_includes response.body, "Showing matters tagged"
    end

    test "renders a theme filter dropdown with the jurisdiction vocabulary" do
      get public_matters_url

      assert_response :success
      assert_select "select#matter-filter-theme" do
        assert_select "option[value='']", text: "Any theme"
        assert_select "option[value='housing']", text: "Housing"
        assert_select "option[value='transportation']", text: "Transportation"
      end
    end

    test "lists theme options in alphabetical order" do
      get public_matters_url

      assert_response :success
      labels = css_select("select#matter-filter-theme option[value!='']").map(&:text)
      assert_equal labels.sort, labels
    end

    test "preselects the active theme in the filter dropdown" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      get public_matters_url(theme: "housing")

      assert_response :success
      assert_select "select#matter-filter-theme option[selected][value='housing']", text: "Housing"
    end

    test "renders the SJUSD theme vocabulary in the dropdown on the SJUSD host" do
      host! "sjusd.civicgallery.org"

      get public_matters_url

      assert_response :success
      assert_select "select#matter-filter-theme option[value='special_education']", text: "Special Education"
      assert_select "select#matter-filter-theme option[value='housing']", count: 0
    end

    test "clear resets both the query and the theme filter" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      get public_matters_url(q: "agreement", theme: "housing")

      assert_response :success
      assert_select ".atlas-matters-filter a.atlas-matters-filter-clear[href=?]", public_matters_path, text: "Clear"
    end

    test "shows clear for a theme-only filter" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      get public_matters_url(theme: "housing")

      assert_response :success
      assert_select ".atlas-matters-filter a.atlas-matters-filter-clear[href=?]", public_matters_path, text: "Clear"
    end

    test "omits clear when no query or theme filter is active" do
      get public_matters_url

      assert_response :success
      assert_select ".atlas-matters-filter a.atlas-matters-filter-clear", text: "Clear", count: 0
    end

    test "shows the primary theme as a tag linking to the theme filter" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      get public_matter_url(@matter)

      assert_response :success
      assert_select "a.atlas-matter-theme-tag[href=?]", public_matters_path(theme: "housing"), text: "Housing"
    end

    test "shows a primary theme tag on each matter row in the index" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      get public_matters_url

      assert_response :success
      assert_select ".atlas-matter-row a.atlas-matter-row-tag[href=?]", public_matters_path(theme: "housing"), text: "Housing"
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

    test "document text search does not rank the broad candidate query" do
      @attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "This staff report describes library outreach funding.",
        character_count: 52
      )
      sql_queries = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _started, _finished, _unique_id, payload|
        sql_queries << payload[:sql]
      end

      begin
        get public_matters_url(q: "library outreach")
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      assert_response :success
      assert_not sql_queries.any? { |sql| sql.include?("ts_rank_cd") }
      assert sql_queries.any? { |sql| sql.include?("ts_headline") }
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
      # Eyebrow + code
      assert_select ".atlas-matter-eyebrow"
      assert_select ".atlas-matter-code", text: "26-575"
      # Meeting reachable in the "Heard at" sidebar
      assert_includes response.body, "Regular meeting"
      # Attachment renders as a numbered "paper" with its name
      assert_select ".atlas-paper h3", text: "Agreement PDF"
      # Extracted text body and summary content
      assert_includes response.body, "Extracted text preview"
      assert_includes response.body, "This agreement authorizes"
      # Summary card label + draft note + AI disclosure (verbatim)
      assert_select ".atlas-summary .atlas-summary-label", text: "Generated summary"
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
      assert_includes response.body, "This attachment has extracted text, but a generated summary has not been added yet."
    end

    test "shows generated summary unavailable reason when source file is not imported" do
      get public_matter_url(@matter)

      assert_response :success
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

    # ---- Atlas-redesign acceptance tests (Phase 3) ----

    test "matter show renders the Atlas shell and loads the Atlas stylesheet" do
      get public_matter_url(@matter)

      assert_response :success
      assert_select "body.atlas-shell"
      assert_select "link[rel=stylesheet][href*=atlas]"
    end

    test "matter sidebar shows sibling matters from the most recent meeting" do
      sibling = Civic::Matter.create!(
        legistar_matter_id: 88_001,
        matter_file: "26-880",
        title: "Sibling agreement"
      )
      sibling.themes.create!(theme_slug: "housing", rank: 1)
      @event.event_items.create!(
        legistar_event_item_id: 129_900,
        civic_matter_id: sibling.id,
        agenda_sequence: 2,
        agenda_number: "3.5",
        title: "Approve sibling agreement"
      )

      get public_matter_url(@matter)

      assert_response :success
      assert_select ".atlas-rail-adjacent .atlas-rail-adjacent-title", text: /26-880/
      assert_select ".atlas-rail-adjacent a.atlas-rail-adjacent-row[href=?]", public_matter_path(sibling)
    end

    test "matter sidebar shows the primary theme tile linking to the theme filter" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      get public_matter_url(@matter)

      assert_response :success
      assert_select ".atlas-rail a.atlas-tile[href=?]", public_matters_path(theme: "housing")
      assert_select ".atlas-rail a.atlas-tile .atlas-tile-name", text: "Housing"
    end

    test "matter header reports the number of documents on file" do
      get public_matter_url(@matter)

      assert_response :success
      # One attachment in the test fixture.
      assert_select ".atlas-matter-side .atlas-matter-docs-count", text: "1"
      assert_select ".atlas-matter-side", text: /Document on file/
    end

    test "matter view omits the Adjacent rail when the matter has never been heard" do
      orphan = Civic::Matter.create!(
        legistar_matter_id: 88_002,
        matter_file: "26-881",
        title: "Never heard"
      )

      get public_matter_url(orphan)

      assert_response :success
      assert_select ".atlas-rail-adjacent", false
      # "Heard at" card is also skipped when there are no event items.
      assert_select ".atlas-rail-card h4", text: /Heard at/i, count: 0
    end

    # ---- Atlas matters index acceptance ----

    test "matters index renders the Atlas shell and the Atlas stylesheet" do
      get public_matters_url

      assert_response :success
      assert_select "body.atlas-shell"
      assert_select "link[rel=stylesheet][href*=atlas]"
    end

    test "matters index renders each matter as an atlas-matter-row with code chip and title" do
      get public_matters_url

      assert_response :success
      assert_select "article.atlas-matter-row" do
        assert_select ".atlas-matter-row-code", text: "26-575"
        assert_select "h2 a[href=?]", public_matter_path(@matter), text: "Agreement approval"
      end
    end

    test "matters index reports a results count above the list" do
      get public_matters_url

      assert_response :success
      assert_select ".atlas-matters-count strong", text: /\A\d+\z/
    end

    test "matters index empty state renders when no matters exist" do
      Civic::EventItem.delete_all
      Civic::MatterAttachment.delete_all
      Civic::Matter.delete_all

      get public_matters_url

      assert_response :success
      assert_select ".atlas-matters-empty"
      assert_select "article.atlas-matter-row", false
    end

    test "matters index theme banner appears when a theme filter is active" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)

      get public_matters_url(theme: "housing")

      assert_response :success
      assert_select ".atlas-matters-banner strong", text: "Housing"
      assert_select ".atlas-matters-banner a.atlas-matters-banner-clear[href=?]", public_matters_path, text: "View all matters"
    end

    # ---- Rate limiting (P0 item 5) ----

    test "repeated matters search requests eventually return 429" do
      PublicRateLimitedSearch::SEARCH_RATE_LIMIT.times do
        get public_matters_url(q: "agreement")
        assert_response :success
      end

      get public_matters_url(q: "agreement")
      assert_response :too_many_requests
    end

    test "matters index browsing without a search query is not throttled" do
      (PublicRateLimitedSearch::SEARCH_RATE_LIMIT + 5).times do
        get public_matters_url
        assert_response :success
      end
    end

    test "rate-limited matters search still returns a 304 ETag on cache hits" do
      get public_matters_url(q: "agreement")
      assert_response :success
      etag = response.headers["ETag"]

      get public_matters_url(q: "agreement"), headers: { "If-None-Match" => etag }
      assert_response :not_modified
    end

    # ---- Cloudflare-aware identity (P0 item 5 follow-up) ----

    test "rate limit uses CF-Connecting-IP when present" do
      PublicRateLimitedSearch::SEARCH_RATE_LIMIT.times do
        get public_matters_url(q: "agreement"),
            headers: { "CF-Connecting-IP" => "203.0.113.1" },
            env: { "REMOTE_ADDR" => "104.22.20.83" }
        assert_response :success
      end

      get public_matters_url(q: "agreement"),
          headers: { "CF-Connecting-IP" => "203.0.113.1" },
          env: { "REMOTE_ADDR" => "104.22.20.83" }
      assert_response :too_many_requests
    end

    test "different CF-Connecting-IP values get separate buckets despite same REMOTE_ADDR" do
      PublicRateLimitedSearch::SEARCH_RATE_LIMIT.times do
        get public_matters_url(q: "agreement"),
            headers: { "CF-Connecting-IP" => "203.0.113.1" },
            env: { "REMOTE_ADDR" => "104.22.20.83" }
        assert_response :success
      end

      # Same edge IP, different real client — must not share the exhausted bucket.
      get public_matters_url(q: "agreement"),
          headers: { "CF-Connecting-IP" => "203.0.113.2" },
          env: { "REMOTE_ADDR" => "104.22.20.83" }
      assert_response :success

      # The original client's bucket is still exhausted.
      get public_matters_url(q: "agreement"),
          headers: { "CF-Connecting-IP" => "203.0.113.1" },
          env: { "REMOTE_ADDR" => "104.22.20.83" }
      assert_response :too_many_requests
    end

    test "without CF-Connecting-IP, falls back to request.remote_ip" do
      PublicRateLimitedSearch::SEARCH_RATE_LIMIT.times do
        get public_matters_url(q: "agreement"),
            env: { "REMOTE_ADDR" => "104.22.20.83" }
        assert_response :success
      end

      get public_matters_url(q: "agreement"),
          env: { "REMOTE_ADDR" => "104.22.20.83" }
      assert_response :too_many_requests
    end

    # ---- Semantic search (Phase 2) ----

    test "semantic search is not used when SEMANTIC_SEARCH_ENABLED is unset" do
      # Default: SEMANTIC_SEARCH_ENABLED is not "true"
      with_env("SEMANTIC_SEARCH_ENABLED", nil) do
        get public_matters_url(q: "agreement")
        assert_response :success
        assert_includes response.body, "26-575"
        # No concept-match label
        assert_select ".atlas-matter-row-semantic", count: 0
      end
    end

    test "semantic search adds concept-match label when enabled" do
      # We need to stub the embedding client so it doesn't hit the API
      # Create a matter that won't match via keyword
      semantic_matter = Civic::Matter.create!(
        legistar_matter_id: 99_100,
        matter_file: "26-900",
        title: "Unrelated zoning variance"
      )
      semantic_attachment = semantic_matter.all_attachments.create!(
        legistar_matter_attachment_id: 99_100,
        name: "Zoning Analysis.pdf"
      )
      semantic_artifact = semantic_attachment.generated_artifacts.create!(
        source_artifact: nil,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "test-v1",
        input_sha256: "semantic-test",
        content: {
          "summary" => "Housing density and affordability analysis.",
          "key_points" => [ "Housing policy" ],
          "limitations" => [ "Generated from extracted text" ],
          "document_status" => "final"
        }
      )
      Search::Embedding.create!(
        civic_jurisdiction: Civic::Jurisdiction.first,
        source_record: semantic_artifact,
        result_record: semantic_matter,
        source_kind: "attachment_summary",
        content_sha256: Digest::SHA256.hexdigest("semantic-test"),
        embedding_model: "text-embedding-3-small",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536,
        metadata: { artifact_id: semantic_artifact.id }
      )

      fake_client = fake_embedding_client([ 0.1 ] * 1536)

      with_embedding_client(fake_client) do
        with_env("SEMANTIC_SEARCH_ENABLED", "true") do
          get public_matters_url(q: "housing affordability")
          assert_response :success

          # The semantic-only matter should appear
          assert_includes response.body, "26-900"
          # It should have the concept-match label
          assert_select ".atlas-matter-row-semantic", count: 1
          assert_select ".atlas-matter-row-semantic-label", text: "Concept match"
        end
      end
    end

    test "semantic search preserves existing keyword results" do
      semantic_matter = Civic::Matter.create!(
        legistar_matter_id: 99_101,
        matter_file: "26-901",
        title: "Unrelated zoning"
      )
      semantic_attachment = semantic_matter.all_attachments.create!(
        legistar_matter_attachment_id: 99_101,
        name: "Analysis.pdf"
      )
      semantic_artifact = semantic_attachment.generated_artifacts.create!(
        source_artifact: nil,
        kind: "attachment_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "test-v1",
        input_sha256: "semantic-test-2",
        content: { "summary" => "Housing affordability." }
      )
      Search::Embedding.create!(
        civic_jurisdiction: Civic::Jurisdiction.first,
        source_record: semantic_artifact,
        result_record: semantic_matter,
        source_kind: "attachment_summary",
        content_sha256: Digest::SHA256.hexdigest("semantic-test-2"),
        embedding_model: "text-embedding-3-small",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536,
        metadata: {}
      )

      fake_client = fake_embedding_client([ 0.1 ] * 1536)

      with_embedding_client(fake_client) do
        with_env("SEMANTIC_SEARCH_ENABLED", "true") do
          get public_matters_url(q: "agreement")
          assert_response :success

          # Original keyword match still appears
          assert_includes response.body, "26-575"
          assert_includes response.body, "Agreement approval"
          # Semantic-only match also appears
          assert_includes response.body, "26-901"
        end
      end
    end

    test "semantic search falls back to keyword-only on client failure" do
      failing_client = fake_embedding_client(nil)
      failing_client.define_singleton_method(:embed) do |_input|
        raise Search::EmbeddingClient::RequestError, "API timeout"
      end

      with_embedding_client(failing_client) do
        with_env("SEMANTIC_SEARCH_ENABLED", "true") do
          get public_matters_url(q: "agreement")
          assert_response :success
          assert_includes response.body, "26-575"
          # No semantic label since nothing matched
          assert_select ".atlas-matter-row-semantic", count: 0
        end
      end
    end

    test "semantic search finds matters through event summaries" do
      event = Civic::Event.create!(
        legistar_event_id: 88_888,
        body_name: "City Council",
        title: "Housing budget hearing",
        event_date: Date.new(2026, 6, 15)
      )
      event.event_items.create!(
        legistar_event_item_id: 88_888,
        civic_matter_id: @matter.id,
        matter_id: @matter.legistar_matter_id,
        agenda_sequence: 2,
        agenda_number: "2.1",
        title: "Budget hearing item"
      )
      event_artifact = Generated::Artifact.create!(
        target: event,
        source_artifact: nil,
        kind: "event_summary",
        status: "succeeded",
        model_identifier: "test-model",
        prompt_version: "test-v1",
        input_sha256: "controller-event-digest",
        content: {
          "summary" => "Council discussed housing budget.",
          "key_topics" => [ "Housing funding" ]
        }
      )
      Search::Embedding.create!(
        civic_jurisdiction: Civic::Jurisdiction.first,
        source_record: event_artifact,
        result_record: event,
        source_kind: "event_summary",
        content_sha256: Digest::SHA256.hexdigest("controller-event-digest"),
        embedding_model: "text-embedding-3-small",
        embedding_dimensions: 1536,
        embedding: [ 0.1 ] * 1536,
        metadata: {}
      )

      fake_client = fake_embedding_client([ 0.1 ] * 1536)

      with_embedding_client(fake_client) do
        with_env("SEMANTIC_SEARCH_ENABLED", "true") do
          get public_matters_url(q: "housing budget")
          assert_response :success

          # The matter linked to the event should appear
          assert_includes response.body, "26-575"
          # The concept-match label should appear since this is a semantic match
          assert_select ".atlas-matter-row-semantic", count: 1
          assert_select ".atlas-matter-row-semantic-label", text: "Concept match"
        end
      end
    end

    test "semantic search filters by theme when theme param is present" do
      thematic_matter = Civic::Matter.create!(
        legistar_matter_id: 99_200,
        matter_file: "26-910",
        title: "Housing density study"
      )
      thematic_matter.themes.create!(theme_slug: "housing", rank: 1)

      non_thematic_matter = Civic::Matter.create!(
        legistar_matter_id: 99_201,
        matter_file: "26-911",
        title: "Transportation plan"
      )
      non_thematic_matter.themes.create!(theme_slug: "transportation", rank: 1)

      # Create attachment_summary embeddings for both matters
      [ thematic_matter, non_thematic_matter ].each do |m|
        att = m.all_attachments.create!(
          legistar_matter_attachment_id: m.legistar_matter_id,
          name: "Attachment for #{m.matter_file}"
        )
        art = att.generated_artifacts.create!(
          source_artifact: nil,
          kind: "attachment_summary",
          status: "succeeded",
          model_identifier: "test-model",
          prompt_version: "test-v1",
          input_sha256: "theme-#{m.id}",
          content: { "summary" => "Content about #{m.title}" }
        )
        Search::Embedding.create!(
          civic_jurisdiction: Civic::Jurisdiction.first,
          source_record: art,
          result_record: m,
          source_kind: "attachment_summary",
          content_sha256: Digest::SHA256.hexdigest("theme-#{m.id}"),
          embedding_model: "text-embedding-3-small",
          embedding_dimensions: 1536,
          embedding: [ 0.1 ] * 1536,
          metadata: {}
        )
      end

      fake_client = fake_embedding_client([ 0.1 ] * 1536)

      with_embedding_client(fake_client) do
        with_env("SEMANTIC_SEARCH_ENABLED", "true") do
          get public_matters_url(q: "content", theme: "housing")
          assert_response :success

          # Should show the housing-themed matter
          assert_includes response.body, "26-910"
          # Should NOT show the transportation-themed matter
          assert_not_includes response.body, "26-911"
        end
      end
    end

    private

    def fake_embedding_client(vector)
      client = Search::EmbeddingClient.new(api_key: "test-key")
      client.define_singleton_method(:embed) do |_input|
        Search::EmbeddingClient::Response.new(
          vector: vector,
          model_name: "text-embedding-3-small",
          usage_metadata: {}
        )
      end
      client
    end

    def with_embedding_client(fake_client)
      original = MattersController.semantic_search_client_factory
      MattersController.semantic_search_client_factory = -> { fake_client }
      yield
    ensure
      MattersController.semantic_search_client_factory = original
    end

    def with_env(key, value)
      original = ENV[key]
      ENV[key] = value
      yield
    ensure
      ENV[key] = original
    end
  end
end

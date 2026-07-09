require "test_helper"

module Public
  class CacheVersionTest < ActiveSupport::TestCase
    test "index cache keys use digests instead of raw query text" do
      jurisdiction = civic_jurisdictions(:sanjose)
      matters_key = CacheVersion.matters_index(query: "Library Outreach", jurisdiction:)
      meetings_key = CacheVersion.meetings_index(
        month: Date.new(2026, 5, 1),
        query: "Library Outreach",
        body_name: "City Council",
        jurisdiction:
      )

      assert_includes matters_key, "public/matters-index/v3/sanjose"
      assert_includes meetings_key, "public/meetings/month-v3/sanjose/2026-05"
      assert_no_match(/Library Outreach|City Council/, matters_key)
      assert_no_match(/Library Outreach|City Council/, meetings_key)
    end

    test "cache keys differ per jurisdiction" do
      sanjose = civic_jurisdictions(:sanjose)
      sjusd = civic_jurisdictions(:sjusd)

      assert_not_equal CacheVersion.events_index(jurisdiction: sanjose),
        CacheVersion.events_index(jurisdiction: sjusd)
      assert_not_equal CacheVersion.matters_index(query: "", jurisdiction: sanjose),
        CacheVersion.matters_index(query: "", jurisdiction: sjusd)
    end

    test "version computation runs no count or max queries" do
      jurisdiction = civic_jurisdictions(:sanjose)

      queries = []
      callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        CacheVersion.events_index(jurisdiction:)
        CacheVersion.matters_index(query: "library", jurisdiction:)
        CacheVersion.meetings_index(month: Date.new(2026, 5, 1), query: "", body_name: "", jurisdiction:)
      end

      assert_empty queries
    end

    test "event index version changes when source records change" do
      jurisdiction = civic_jurisdictions(:sanjose)
      first_key = CacheVersion.events_index(jurisdiction:)

      travel 1.second do
        Civic::Event.create!(
          legistar_event_id: 7621,
          body_name: "City Council",
          event_date: Date.new(2026, 5, 19)
        )
      end

      assert_not_equal first_key, CacheVersion.events_index(jurisdiction: jurisdiction.reload)
    end

    test "matter detail version changes when generated summary changes" do
      matter = Civic::Matter.create!(legistar_matter_id: 15886, matter_file: "26-575")
      attachment = matter.all_attachments.create!(legistar_matter_attachment_id: 39135, name: "Agreement")
      extracted_text = attachment.extracted_texts.create!(
        extractor_name: "pdftotext",
        status: "ok",
        content: "Agreement body",
        character_count: 14
      )
      jurisdiction = matter.civic_jurisdiction

      first_key = CacheVersion.matter_show(matter, jurisdiction: jurisdiction.reload)

      travel 1.second do
        attachment.generated_artifacts.create!(
          source_artifact: extracted_text,
          kind: Generated::SummarizeMatterAttachment::KIND,
          status: "succeeded",
          model_identifier: "test-model",
          prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION,
          input_sha256: "abc",
          content: { "summary" => "ok" }
        )
      end

      assert_not_equal first_key, CacheVersion.matter_show(matter, jurisdiction: jurisdiction.reload)
    end

    test "writes scoped to one jurisdiction do not bump the other" do
      sanjose = civic_jurisdictions(:sanjose)
      sjusd = civic_jurisdictions(:sjusd)
      sanjose_key = CacheVersion.events_index(jurisdiction: sanjose)
      sjusd_key = CacheVersion.events_index(jurisdiction: sjusd)

      travel 1.second do
        Civic::Event.create!(
          legistar_event_id: 7622,
          body_name: "City Council",
          event_date: Date.new(2026, 5, 20)
        )
      end

      assert_not_equal sanjose_key, CacheVersion.events_index(jurisdiction: sanjose.reload)
      assert_equal sjusd_key, CacheVersion.events_index(jurisdiction: sjusd.reload)
    end
  end
end

require "test_helper"

module Public
  class CacheVersionTest < ActiveSupport::TestCase
    test "index cache keys use digests instead of raw query text" do
      matters_key = CacheVersion.matters_index(query: "Library Outreach")
      meetings_key = CacheVersion.meetings_index(
        month: Date.new(2026, 5, 1),
        query: "Library Outreach",
        body_name: "City Council"
      )

      assert_includes matters_key, "public/matters-index/v1"
      assert_includes meetings_key, "public/meetings/month-v1/2026-05"
      assert_no_match(/Library Outreach|City Council/, matters_key)
      assert_no_match(/Library Outreach|City Council/, meetings_key)
    end

    test "event index version changes when source records change" do
      first_key = CacheVersion.events_index

      travel 1.second do
        Civic::Event.create!(
          legistar_event_id: 7621,
          body_name: "City Council",
          event_date: Date.new(2026, 5, 19)
        )
      end

      assert_not_equal first_key, CacheVersion.events_index
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

      first_key = CacheVersion.matter_show(matter)

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

      assert_not_equal first_key, CacheVersion.matter_show(matter)
    end
  end
end

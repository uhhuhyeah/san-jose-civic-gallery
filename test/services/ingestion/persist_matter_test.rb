require "test_helper"

module Ingestion
  class PersistMatterTest < ActiveSupport::TestCase
    test "persists a matter and raw snapshot" do
      matter_payload = {
        "MatterId" => 15915,
        "MatterFile" => "26-602",
        "MatterTitle" => "Language Access Instructions",
        "MatterBodyName" => "City Council",
        "MatterTypeName" => "Consent Agenda",
        "MatterStatusName" => "Agenda Ready",
        "MatterRequester" => "City Clerk's Office",
        "MatterIntroDate" => "2026-05-11T00:00:00",
        "MatterLastModifiedUtc" => "2026-05-13T18:42:39.207"
      }

      matter, snapshot = PersistMatter.call(
        matter_payload:,
        source_system: "legistar.sanjose",
        request_url: "https://example.test/Matters/15915",
        fetched_at: Time.zone.parse("2026-05-15 08:30:00"),
        http_status: 200,
        response_sha256: "ghi789"
      )

      assert_equal 15915, matter.legistar_matter_id
      assert_equal "26-602", matter.matter_file
      assert_equal "Language Access Instructions", matter.title
      assert_equal "matter", snapshot.resource_type
      assert_equal "15915", snapshot.source_id
      assert_equal "legistar.sanjose", matter.source_system
      assert_equal snapshot.id, matter.last_source_snapshot_id
    end
  end
end

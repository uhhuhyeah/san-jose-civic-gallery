require "test_helper"

module Civic
  class JurisdictionDataVersionTest < ActiveSupport::TestCase
    setup do
      @sanjose = civic_jurisdictions(:sanjose)
      @sjusd = civic_jurisdictions(:sjusd)
    end

    test "data_version falls back to updated_at before any bump" do
      assert_nil @sanjose.data_updated_at
      assert_equal @sanjose.updated_at.utc.iso8601(6), @sanjose.data_version
    end

    test "bump_data_version! advances only the given jurisdiction" do
      Jurisdiction.bump_data_version!(@sanjose.id)

      assert_not_nil @sanjose.reload.data_updated_at
      assert_nil @sjusd.reload.data_updated_at
    end

    test "bump_data_version! with nil advances every jurisdiction" do
      Jurisdiction.bump_data_version!(nil)

      assert_not_nil @sanjose.reload.data_updated_at
      assert_not_nil @sjusd.reload.data_updated_at
    end

    test "matter theme writes bump through the matter's jurisdiction" do
      matter = Civic::Matter.create!(legistar_matter_id: 9001, matter_file: "26-901")
      version_before = @sanjose.reload.data_version

      travel 1.second do
        matter.themes.create!(theme_slug: "housing")
      end

      assert_not_equal version_before, @sanjose.reload.data_version
      assert_nil @sjusd.reload.data_updated_at
    end

    test "extracted text writes bump through the attachment's jurisdiction" do
      matter = Civic::Matter.create!(legistar_matter_id: 9002, matter_file: "26-902")
      attachment = matter.all_attachments.create!(legistar_matter_attachment_id: 9102, name: "Report")
      version_before = @sanjose.reload.data_version

      travel 1.second do
        attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "ok", content: "Body", character_count: 4)
      end

      assert_not_equal version_before, @sanjose.reload.data_version
      assert_nil @sjusd.reload.data_updated_at
    end

    test "destroying a record bumps the jurisdiction" do
      event = Civic::Event.create!(legistar_event_id: 9003, body_name: "City Council", event_date: Date.new(2026, 5, 19))
      version_before = @sanjose.reload.data_version

      travel 1.second do
        event.destroy!
      end

      assert_not_equal version_before, @sanjose.reload.data_version
    end
  end
end

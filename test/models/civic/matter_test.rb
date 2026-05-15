require "test_helper"

module Civic
  class MatterTest < ActiveSupport::TestCase
    test "requires legistar_matter_id and matter_file" do
      matter = Matter.new

      assert_not matter.valid?
      assert_includes matter.errors[:legistar_matter_id], "can't be blank"
      assert_includes matter.errors[:matter_file], "can't be blank"
    end

    test "destroying a matter destroys tombstone attachments alongside source-present ones" do
      matter = Matter.create!(legistar_matter_id: 88001, matter_file: "26-700")
      live = matter.all_attachments.create!(legistar_matter_attachment_id: 5001, name: "Live attachment")
      tombstone = matter.all_attachments.create!(
        legistar_matter_attachment_id: 5002,
        name: "Removed upstream",
        source_present: false,
        source_missing_at: Time.current
      )

      assert_difference -> { MatterAttachment.count }, -2 do
        matter.destroy!
      end

      assert_not MatterAttachment.exists?(live.id)
      assert_not MatterAttachment.exists?(tombstone.id)
    end

    test "attachments association returns only source-present rows" do
      matter = Matter.create!(legistar_matter_id: 88002, matter_file: "26-701")
      live = matter.all_attachments.create!(legistar_matter_attachment_id: 6001, name: "Live")
      matter.all_attachments.create!(
        legistar_matter_attachment_id: 6002,
        name: "Tombstone",
        source_present: false,
        source_missing_at: Time.current
      )

      assert_equal [ live.id ], matter.attachments.pluck(:id)
      assert_equal 2, matter.all_attachments.count
    end
  end
end

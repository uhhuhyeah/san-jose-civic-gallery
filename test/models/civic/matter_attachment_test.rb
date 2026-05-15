require "test_helper"

module Civic
  class MatterAttachmentTest < ActiveSupport::TestCase
    setup do
      @matter = Matter.create!(
        legistar_matter_id: 15915,
        matter_file: "26-602"
      )
    end

    test "requires legistar_matter_attachment_id and name" do
      attachment = MatterAttachment.new(matter: @matter)

      assert_not attachment.valid?
      assert_includes attachment.errors[:legistar_matter_attachment_id], "can't be blank"
      assert_includes attachment.errors[:name], "can't be blank"
    end
  end
end

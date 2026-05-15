require "test_helper"

module Civic
  class MatterTest < ActiveSupport::TestCase
    test "requires legistar_matter_id and matter_file" do
      matter = Matter.new

      assert_not matter.valid?
      assert_includes matter.errors[:legistar_matter_id], "can't be blank"
      assert_includes matter.errors[:matter_file], "can't be blank"
    end
  end
end

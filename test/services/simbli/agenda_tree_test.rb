require "test_helper"

module Simbli
  class AgendaTreeTest < ActiveSupport::TestCase
    test "flattens the tree depth-first and preserves order" do
      payload = JSON.parse(file_fixture("simbli/agenda_tree.json").read)
      items = AgendaTree.parse(payload)

      assert_equal [ 100, 101, 200, 201 ], items.map(&:agenda_id)
      assert_equal [ 1, 2, 3, 4 ], items.map(&:position)
      assert_equal "A. Call to Order", items.first.title
    end

    test "marks attachment-bearing items" do
      payload = JSON.parse(file_fixture("simbli/agenda_tree.json").read)
      items = AgendaTree.parse(payload)

      assert_equal [ 201 ], items.select(&:has_attachment).map(&:agenda_id)
    end

    test "parses the captured production agenda payload" do
      raw = JSON.parse(Rails.root.join("docs/spikes/simbli/payloads/meeting-57394.json").read)
      items = AgendaTree.parse(raw["apiResponses"][0]["body"])

      assert_equal 55, items.size
      assert_equal 24, items.count(&:has_attachment)
    end
  end
end

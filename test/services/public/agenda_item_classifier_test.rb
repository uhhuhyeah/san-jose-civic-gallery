require "test_helper"

module Public
  class AgendaItemClassifierTest < ActiveSupport::TestCase
    setup do
      @event = Civic::Event.create!(
        legistar_event_id: 8001,
        body_name: "Test Body",
        event_date: Date.new(2026, 6, 1)
      )
    end

    test "tags an item with civic_matter_id as substantive regardless of agenda_number" do
      matter = Civic::Matter.create!(legistar_matter_id: 50_000, matter_file: "26-500")
      item = build_item(civic_matter_id: matter.id, agenda_number: "3.")

      assert_equal :substantive, AgendaItemClassifier.classify(item)
    end

    test "tags lettered agenda markers (a)..(z) as section" do
      %w[(a) (b) (c) (d) (z)].each do |marker|
        item = build_item(agenda_number: marker)
        assert_equal :section, AgendaItemClassifier.classify(item),
                     "expected #{marker.inspect} to classify as :section"
      end
    end

    test "tags a bullet '•' as section" do
      item = build_item(agenda_number: "•")
      assert_equal :section, AgendaItemClassifier.classify(item)
    end

    test "tolerates surrounding whitespace in section markers" do
      item = build_item(agenda_number: " (d) ")
      assert_equal :section, AgendaItemClassifier.classify(item)
    end

    test "tags an item with no matter and no recognizable marker as notice" do
      item = build_item(agenda_number: nil, title: "How to observe the meeting")
      assert_equal :notice, AgendaItemClassifier.classify(item)
    end

    test "tags a digit-numbered item without any matter linkage as notice" do
      # An item with no civic_matter_id and no matter_id is boilerplate. The
      # digit marker alone does not make it substantive.
      item = build_item(agenda_number: "3.", civic_matter_id: nil, matter_id: nil, title: "Free-form notice")
      assert_equal :notice, AgendaItemClassifier.classify(item)
    end

    test "tags an item with only the upstream matter_id (sync pending) as substantive" do
      # Upstream Legistar matter id is present but the local FK is not — the
      # matter hasn't synced yet. Still substantive; the view shows a pending
      # hint inline.
      item = build_item(matter_id: 99_999, civic_matter_id: nil, agenda_number: "1.", title: "Pending matter")
      assert_equal :substantive, AgendaItemClassifier.classify(item)
    end

    test "tag returns an array of [kind, item] pairs in input order" do
      matter = Civic::Matter.create!(legistar_matter_id: 50_010, matter_file: "26-510")
      a = build_item(agenda_number: "(a)", title: "Call to order")
      b = build_item(civic_matter_id: matter.id, agenda_number: "1.", title: "Substantive")
      c = build_item(title: "Levine Act boilerplate")

      tagged = AgendaItemClassifier.tag([ a, b, c ])

      assert_equal [ :section, :substantive, :notice ], tagged.map(&:first)
      assert_equal [ a, b, c ], tagged.map(&:last)
    end

    test "real T&E-style mix lands in the 25-30% substantive ratio band" do
      matter1 = Civic::Matter.create!(legistar_matter_id: 50_021, matter_file: "26-A")
      matter2 = Civic::Matter.create!(legistar_matter_id: 50_022, matter_file: "26-B")
      matter3 = Civic::Matter.create!(legistar_matter_id: 50_023, matter_file: "26-C")
      matter4 = Civic::Matter.create!(legistar_matter_id: 50_024, matter_file: "26-D")

      items = [
        # 11 pre-agenda notices (translation, how to observe, public comment, etc.)
        *Array.new(11) { build_item(title: "Procedural notice") },
        # Section markers (a) (b) (c) (d) plus two bullets
        build_item(agenda_number: "(a)", title: "Call to Order"),
        build_item(agenda_number: "(b)", title: "Review of Work Plan"),
        build_item(agenda_number: "(c)", title: "Consent Calendar"),
        build_item(agenda_number: "(d)", title: "Reports to Committee"),
        # 4 substantive matters under (d)
        build_item(civic_matter_id: matter1.id, agenda_number: "1.", title: "CC 25-010"),
        build_item(civic_matter_id: matter2.id, agenda_number: "2.", title: "CC 25-011"),
        build_item(civic_matter_id: matter3.id, agenda_number: "3.", title: "CC 25-012"),
        build_item(civic_matter_id: matter4.id, agenda_number: "4.", title: "CC 25-013"),
        # Open Forum / Adjournment
        build_item(agenda_number: "•", title: "Open Forum"),
        build_item(agenda_number: "•", title: "Adjournment"),
        # Trailing notices
        *Array.new(3) { build_item(title: "Closing notice") }
      ]

      tagged = AgendaItemClassifier.tag(items)
      ratio = tagged.count { |kind, _| kind == :substantive }.to_f / tagged.length

      assert_in_delta 0.18, ratio, 0.03,
                      "T&E-style agenda landed at #{(ratio * 100).round(1)}%, outside the expected band"
    end

    private

    def build_item(attrs = {})
      defaults = {
        civic_event_id: @event.id,
        legistar_event_item_id: rand(100_000_000),
        agenda_sequence: 1,
        source_present: true
      }
      Civic::EventItem.new(defaults.merge(attrs))
    end
  end
end

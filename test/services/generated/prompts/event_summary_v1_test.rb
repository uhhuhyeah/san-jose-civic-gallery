require "test_helper"

module Generated
  module Prompts
    class EventSummaryV1Test < ActiveSupport::TestCase
      setup do
        @event = Civic::Event.create!(
          legistar_event_id: 80_001,
          body_name: "City Council",
          title: "Regular Meeting",
          event_date: Date.new(2026, 5, 12)
        )
      end

      test "labels the meeting with its body and jurisdiction" do
        prompt = EventSummaryV1.build(event: @event, source_text: "Item 1", theme_summary: "")

        assert_includes prompt[:user_prompt], "Meeting: City Council (#{@event.civic_jurisdiction.short_name})"
        assert_includes prompt[:user_prompt], "Date: 2026-05-12"
      end

      test "system prompt forbids stating outcomes" do
        prompt = normalized_system_prompt

        assert_includes prompt, "Never state an outcome"
        assert_includes prompt, "vote counts or tallies"
      end

      test "system prompt forbids restating requested-action titles as accomplished" do
        prompt = normalized_system_prompt

        assert_includes prompt, "Never restate them as accomplished"
        assert_includes prompt, "ratified"
      end

      test "system prompt tells key_topics to name the subject, not the requested action" do
        prompt = normalized_system_prompt

        assert_includes prompt, "Name the subject, not the requested action"
        assert_includes prompt, "becomes \"Permanent PE exemptions for high school students\""
      end

      test "theme summary appears in the user prompt but is excluded from the hash" do
        without_themes = EventSummaryV1.build(event: @event, source_text: "Item 1", theme_summary: "")
        with_themes = EventSummaryV1.build(event: @event, source_text: "Item 1", theme_summary: "- 1: Housing")

        assert_includes with_themes[:user_prompt], "- 1: Housing"
        # Same source text means the same idempotency hash regardless of themes.
        assert_equal without_themes[:sent_content_sha256], with_themes[:sent_content_sha256]
      end

      test "the hash changes when the source record changes" do
        first = EventSummaryV1.build(event: @event, source_text: "Item 1", theme_summary: "")
        second = EventSummaryV1.build(event: @event, source_text: "Item 1 amended", theme_summary: "")

        assert_not_equal first[:sent_content_sha256], second[:sent_content_sha256]
      end

      test "truncates source text beyond the limit and flags it" do
        prompt = EventSummaryV1.build(event: @event, source_text: "a" * 50, theme_summary: "", max_input_chars: 10)

        assert prompt[:truncated]
        assert_includes prompt[:user_prompt], EventSummaryV1::TRUNCATION_MARKER.strip
      end

      test "uses a placeholder when no record text is available" do
        prompt = EventSummaryV1.build(event: @event, source_text: "", theme_summary: "")

        assert_includes prompt[:user_prompt], EventSummaryV1::NO_RECORD_TEXT
        assert_not prompt[:truncated]
      end

      test "marks a past meeting as already held and instructs past tense" do
        prompt = EventSummaryV1.build(event: @event, source_text: "Item 1", theme_summary: "", now: Date.new(2026, 5, 20))

        assert_includes prompt[:user_prompt], "Meeting status: already held"
        assert_includes prompt[:system_prompt], "If it has been held, write in the past tense"
      end

      test "marks an upcoming meeting as not yet held" do
        prompt = EventSummaryV1.build(event: @event, source_text: "Item 1", theme_summary: "", now: Date.new(2026, 5, 1))

        assert_includes prompt[:user_prompt], "upcoming, not yet held"
      end

      test "the held flag changes the hash so a meeting regenerates once after it occurs" do
        upcoming = EventSummaryV1.build(event: @event, source_text: "Item 1", theme_summary: "", now: Date.new(2026, 5, 1))
        held = EventSummaryV1.build(event: @event, source_text: "Item 1", theme_summary: "", now: Date.new(2026, 5, 20))

        assert_not_equal upcoming[:sent_content_sha256], held[:sent_content_sha256]
      end

      private

      # The system prompt is line-wrapped, so collapse whitespace before
      # asserting on phrases that may span a wrap.
      def normalized_system_prompt
        EventSummaryV1.build(event: @event, source_text: "Item 1", theme_summary: "")[:system_prompt].gsub(/\s+/, " ")
      end
    end
  end
end

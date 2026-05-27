require "test_helper"
require "digest"

module Generated
  module Prompts
    class MonthlyRoundupV1Test < ActiveSupport::TestCase
      setup do
        Civic::Jurisdiction.seed_defaults!
        @jurisdiction = Civic::Jurisdiction.default
        @period = Civic::RoundupPeriod.for_month(
          jurisdiction: @jurisdiction,
          year: 2026,
          month: 5,
        )
        @period_start = @period.period_start
        @period_end = @period.period_end

        # Create a decision matter (passed in the window, with "housing" theme).
        @decision_matter = Civic::Matter.create!(
          legistar_matter_id: 71_001,
          matter_file: "26-100",
          title: "Zoning changes for downtown housing",
          passed_date: Date.new(2026, 5, 15),
          source_system: "legistar.sanjose",
        )
        @decision_matter.themes.create!(theme_slug: "housing", rank: 1)

        # Create an event with a succeeded summary artifact.
        @event = create_event(legistar_event_id: 82_001, event_date: Date.new(2026, 5, 12))
        create_summary_artifact(@event)

        @activity = Public::MonthlyActivity.new(
          jurisdiction: @jurisdiction,
          period_start: @period_start,
          period_end: @period_end,
        )
      end

      # --- return-value shape -----------------------------------------------

      test "build returns hash with the required keys" do
        result = Generated::Prompts::MonthlyRoundupV1.build(
          period: @period,
          activity: @activity,
        )

        assert result.is_a?(Hash)
        required_keys = %i[
          system_prompt
          user_prompt
          sent_content
          sent_character_count
          sent_content_sha256
          truncated
        ]
        assert_includes result.keys, :system_prompt
        assert_includes result.keys, :user_prompt
        assert_includes result.keys, :sent_content
        assert_includes result.keys, :sent_character_count
        assert_includes result.keys, :sent_content_sha256
        assert_includes result.keys, :truncated
      end

      # --- system prompt content --------------------------------------------

      test "system_prompt contains the forbidden-phrase rule" do
        result = build_prompt
        lower = result[:system_prompt].downcase

        assert_includes lower, "delve"
        assert_includes lower, "in conclusion"
        assert_includes lower, "tapestry"
        assert_includes lower, "em dash"
      end

      test "system_prompt names the JSON output keys" do
        result = build_prompt
        sp = result[:system_prompt]

        assert_includes sp, "headline"
        assert_includes sp, "intro"
        assert_includes sp, "storyline"
      end

      # --- user prompt content ----------------------------------------------

      test "user_prompt contains the period label" do
        result = build_prompt
        assert_includes result[:user_prompt], "May 2026"
      end

      test "user_prompt contains the jurisdiction short name" do
        result = build_prompt
        assert_includes result[:user_prompt], "San Jose"
      end

      test "user_prompt contains the decision matter display_name" do
        result = build_prompt
        assert_includes result[:user_prompt], @decision_matter.display_name
      end

      test "user_prompt contains the meeting summary text" do
        result = build_prompt
        assert_includes result[:user_prompt], "Council discussed housing."
      end

      test "user_prompt contains Themes gaining momentum header" do
        result = build_prompt
        assert_includes result[:user_prompt], "Themes gaining momentum"
      end

      # --- sent_content exclusion rules -------------------------------------

      test "sent_content does NOT contain the theme-momentum section" do
        result = build_prompt
        refute_includes result[:sent_content], "Themes gaining momentum"
      end

      test "sent_content does NOT contain the quiet-month flag" do
        result = build_prompt
        refute_includes result[:sent_content], "quiet month"
        refute_includes result[:sent_content], "quiet_month"
      end

      # --- sent_content hashing stability -----------------------------------

      test "sent_content_sha256 is stable across identical builds" do
        result1 = build_prompt
        result2 = build_prompt

        assert_equal result1[:sent_content_sha256], result2[:sent_content_sha256]
      end

      test "sent_content_sha256 changes when a new decision is added" do
        hash1 = build_prompt[:sent_content_sha256]

        # Add another in-window decision.
        Civic::Matter.create!(
          legistar_matter_id: 71_002,
          matter_file: "26-200",
          title: "New parking ordinance",
          passed_date: Date.new(2026, 5, 20),
          source_system: "legistar.sanjose",
        )

        # Rebuild activity so it picks up the new matter.
        new_activity = Public::MonthlyActivity.new(
          jurisdiction: @jurisdiction,
          period_start: @period_start,
          period_end: @period_end,
        )

        hash2 = Generated::Prompts::MonthlyRoundupV1.build(
          period: @period,
          activity: new_activity,
        )[:sent_content_sha256]

        refute_equal hash1, hash2
      end

      # --- sent_character_count matches sent_content length -----------------

      test "sent_character_count equals sent_content length" do
        result = build_prompt
        assert_equal result[:sent_content].length, result[:sent_character_count]
      end

      # --- truncated defaults to false when within limit --------------------

      test "truncated is false when facts fit within default max_input_chars" do
        result = build_prompt
        refute result[:truncated]
      end

      # --- no em dashes anywhere in output ----------------------------------

      test "built output contains no em-dash character" do
        result = build_prompt
        em_dash = "\u2014"
        assert_not_includes result[:system_prompt], em_dash
        assert_not_includes result[:user_prompt], em_dash
        assert_not_includes result[:sent_content], em_dash
      end

      private

      def build_prompt
        Generated::Prompts::MonthlyRoundupV1.build(
          period: @period,
          activity: @activity,
        )
      end

      def create_event(legistar_event_id:, event_date:)
        Civic::Event.create!(
          legistar_event_id: legistar_event_id,
          body_name: "City Council",
          title: "Regular Meeting",
          event_date: event_date,
          source_system: "legistar.sanjose",
          source_present: true,
        )
      end

      def create_summary_artifact(event, status: "succeeded")
        Generated::Artifact.create!(
          target: event,
          kind: Generated::SummarizeEvent::KIND,
          model_identifier: "test-event-model",
          prompt_version: Generated::SummarizeEvent::PROMPT::VERSION,
          input_sha256: "test-monthly-#{event.id}",
          status: status,
          content: { "summary" => "Council discussed housing.", "key_topics" => ["Housing"], "limitations" => [] },
          generated_at: Time.current,
        )
      end
    end
  end
end

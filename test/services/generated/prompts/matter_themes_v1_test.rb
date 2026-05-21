require "test_helper"

module Generated
  module Prompts
    class MatterThemesV1Test < ActiveSupport::TestCase
      setup do
        @matter = Civic::Matter.create!(
          legistar_matter_id: 40_001,
          matter_file: "26-200",
          title: "Rezoning for affordable housing on First Street"
        )
      end

      test "embeds the full taxonomy in the system prompt" do
        prompt = MatterThemesV1.build(matter: @matter, source_text: "Body text.")

        Civic::ThemeTaxonomy.slugs_for(@matter.civic_jurisdiction).each do |slug|
          assert_includes prompt[:system_prompt], slug
        end
      end

      test "instructs primary-subject tagging, a cap, and procedural exclusion" do
        prompt = MatterThemesV1.build(matter: @matter, source_text: "Body text.")
        system_prompt = prompt[:system_prompt]

        assert_includes system_prompt, "primary subject"
        assert_includes system_prompt, "at most two"
        assert_match(/approval of\s+minutes/, system_prompt)
        assert_match(/empty array for procedural/, system_prompt)
      end

      test "instructs ceremonial and incidental-association handling" do
        prompt = MatterThemesV1.build(matter: @matter, source_text: "Body text.")
        system_prompt = prompt[:system_prompt]

        assert_match(/[Cc]eremonial and sponsorship/, system_prompt)
        assert_match(/incidental association/, system_prompt)
      end

      test "guards against Budget and Economic Development catch-alls and lists travel authorizations" do
        prompt = MatterThemesV1.build(matter: @matter, source_text: "Body text.")
        system_prompt = prompt[:system_prompt]

        assert_match(/catch-all/, system_prompt)
        assert_includes system_prompt, "Economic Development only"
        assert_match(/travel authorization/, system_prompt)
      end

      test "states the confused-theme boundaries" do
        prompt = MatterThemesV1.build(matter: @matter, source_text: "Body text.")
        system_prompt = prompt[:system_prompt]

        assert_match(/Vision Zero.*Transportation/m, system_prompt)
        assert_match(/Utilities, not Economic Development/, system_prompt)
        assert_match(/funds or budgets another program/, system_prompt)
      end

      test "version is matter_themes_v5" do
        assert_equal "matter_themes_v5", MatterThemesV1::VERSION
      end

      test "includes matter identity and source text in the user prompt" do
        prompt = MatterThemesV1.build(matter: @matter, source_text: "Discusses zoning variance.")

        assert_includes prompt[:user_prompt], "26-200"
        assert_includes prompt[:user_prompt], "Rezoning for affordable housing on First Street"
        assert_includes prompt[:user_prompt], "Discusses zoning variance."
      end

      test "falls back to a placeholder when no source text is supplied" do
        prompt = MatterThemesV1.build(matter: @matter, source_text: "  ")

        assert_includes prompt[:user_prompt], MatterThemesV1::NO_BODY_TEXT
        assert_equal false, prompt[:truncated]
      end

      test "truncates overlong source text and flags it" do
        prompt = MatterThemesV1.build(matter: @matter, source_text: "x" * 50, max_input_chars: 10)

        assert_equal true, prompt[:truncated]
        assert_includes prompt[:user_prompt], MatterThemesV1::TRUNCATION_MARKER
      end

      test "hash changes when source text changes" do
        a = MatterThemesV1.build(matter: @matter, source_text: "First body")
        b = MatterThemesV1.build(matter: @matter, source_text: "Second body")

        assert_not_equal a[:sent_content_sha256], b[:sent_content_sha256]
      end
    end
  end
end

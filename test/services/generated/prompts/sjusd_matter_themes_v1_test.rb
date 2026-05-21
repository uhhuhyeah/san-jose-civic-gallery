require "test_helper"

module Generated
  module Prompts
    class SjusdMatterThemesV1Test < ActiveSupport::TestCase
      setup do
        @matter = Civic::Matter.create!(
          source_system: "simbli.sjusd",
          source_matter_id: "sjusd:57394:1",
          matter_file: "SJUSD-57394-1",
          title: "Adopt new mathematics curriculum"
        )
      end

      test "version is sjusd_matter_themes_v1" do
        assert_equal "sjusd_matter_themes_v1", SjusdMatterThemesV1::VERSION
      end

      test "embeds the SJUSD taxonomy, not the city one" do
        prompt = SjusdMatterThemesV1.build(matter: @matter, source_text: "Body text.")

        Civic::ThemeTaxonomy.slugs_for(@matter.civic_jurisdiction).each do |slug|
          assert_includes prompt[:system_prompt], slug
        end
        assert_includes prompt[:system_prompt], "School Safety & Climate"
        assert_not_includes prompt[:system_prompt], "land_use_zoning"
      end

      test "states school-district boundaries and procedural exclusion" do
        system_prompt = SjusdMatterThemesV1.build(matter: @matter, source_text: "Body text.")[:system_prompt]

        assert_match(/Special Education, not Curriculum/, system_prompt)
        assert_match(/Facilities & Bonds, not Budget/, system_prompt)
        assert_match(/empty array for procedural/, system_prompt)
        assert_includes system_prompt, "at most two"
      end

      test "includes matter identity and source text in the user prompt" do
        prompt = SjusdMatterThemesV1.build(matter: @matter, source_text: "Discusses math adoption.")

        assert_includes prompt[:user_prompt], "SJUSD-57394-1"
        assert_includes prompt[:user_prompt], "Adopt new mathematics curriculum"
        assert_includes prompt[:user_prompt], "Discusses math adoption."
      end
    end
  end
end

require "test_helper"

module Civic
  class ThemeTaxonomyTest < ActiveSupport::TestCase
    def sanjose
      civic_jurisdictions(:sanjose)
    end

    def sjusd
      civic_jurisdictions(:sjusd)
    end

    test "each jurisdiction's slugs are unique and non-blank" do
      [ sanjose, sjusd ].each do |jurisdiction|
        slugs = ThemeTaxonomy.slugs_for(jurisdiction)

        assert_equal slugs.uniq, slugs
        assert(slugs.all?(&:present?))
      end
    end

    test "every theme has a label" do
      [ ThemeTaxonomy::SANJOSE, ThemeTaxonomy::SJUSD ].each do |themes|
        assert(themes.all? { |theme| theme[:label].present? })
      end
    end

    test "valid_slug? is scoped to the jurisdiction's vocabulary" do
      assert ThemeTaxonomy.valid_slug?("housing", sanjose)
      assert_not ThemeTaxonomy.valid_slug?("housing", sjusd)

      assert ThemeTaxonomy.valid_slug?("special_education", sjusd)
      assert_not ThemeTaxonomy.valid_slug?("special_education", sanjose)

      assert_not ThemeTaxonomy.valid_slug?("not_a_theme", sanjose)
    end

    test "label_for resolves per jurisdiction" do
      assert_equal "Housing", ThemeTaxonomy.label_for("housing", sanjose)
      assert_equal "Special Education", ThemeTaxonomy.label_for("special_education", sjusd)
      assert_nil ThemeTaxonomy.label_for("housing", sjusd)
    end

    test "a slug shared across vocabularies is valid in each" do
      assert ThemeTaxonomy.valid_slug?("budget_finance", sanjose)
      assert ThemeTaxonomy.valid_slug?("budget_finance", sjusd)
    end

    test "unknown or nil jurisdiction falls back to the city vocabulary" do
      assert_equal ThemeTaxonomy::SANJOSE, ThemeTaxonomy.themes_for(nil)
      assert_equal ThemeTaxonomy::SANJOSE, ThemeTaxonomy.themes_for("unknown")
    end

    test "accepts a slug string in place of a jurisdiction object" do
      assert ThemeTaxonomy.valid_slug?("special_education", "sjusd")
      assert_equal "Housing", ThemeTaxonomy.label_for("housing", "sanjose")
    end
  end
end

require "test_helper"

module Civic
  class ThemeTaxonomyTest < ActiveSupport::TestCase
    test "slugs are unique and non-blank" do
      slugs = ThemeTaxonomy.slugs

      assert_equal slugs.uniq, slugs
      assert(slugs.all?(&:present?))
    end

    test "every theme has a label" do
      assert(ThemeTaxonomy::THEMES.all? { |theme| theme[:label].present? })
    end

    test "valid_slug? recognizes known and unknown slugs" do
      assert ThemeTaxonomy.valid_slug?("housing")
      assert_not ThemeTaxonomy.valid_slug?("not_a_theme")
    end

    test "label_for returns the display label or nil" do
      assert_equal "Housing", ThemeTaxonomy.label_for("housing")
      assert_nil ThemeTaxonomy.label_for("not_a_theme")
    end
  end
end

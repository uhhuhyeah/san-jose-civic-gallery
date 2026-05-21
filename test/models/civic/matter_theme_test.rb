require "test_helper"

module Civic
  class MatterThemeTest < ActiveSupport::TestCase
    setup do
      @matter = Matter.create!(legistar_matter_id: 91001, matter_file: "26-900")
    end

    test "requires a theme_slug from the taxonomy" do
      theme = @matter.themes.build(theme_slug: "not_a_theme")

      assert_not theme.valid?
      assert_includes theme.errors[:theme_slug], "is not included in the list"
    end

    test "accepts a known theme_slug" do
      theme = @matter.themes.build(theme_slug: "housing")

      assert theme.valid?
    end

    test "is unique per matter and theme" do
      @matter.themes.create!(theme_slug: "housing")
      duplicate = @matter.themes.build(theme_slug: "housing")

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:theme_slug], "has already been taken"
    end

    test "label resolves through the taxonomy" do
      theme = @matter.themes.create!(theme_slug: "land_use_zoning")

      assert_equal "Land Use & Zoning", theme.label
    end

    test "validates the slug against the matter's jurisdiction vocabulary" do
      sjusd_matter = Matter.create!(
        source_system: "simbli.sjusd",
        source_matter_id: "sjusd:1:1",
        matter_file: "SJUSD-1-1"
      )

      assert sjusd_matter.themes.build(theme_slug: "special_education").valid?

      city_only = sjusd_matter.themes.build(theme_slug: "housing")
      assert_not city_only.valid?
      assert_includes city_only.errors[:theme_slug], "is not included in the list"
    end

    test "label resolves through the matter's jurisdiction" do
      sjusd_matter = Matter.create!(
        source_system: "simbli.sjusd",
        source_matter_id: "sjusd:1:2",
        matter_file: "SJUSD-1-2"
      )
      theme = sjusd_matter.themes.create!(theme_slug: "special_education")

      assert_equal "Special Education", theme.label
    end

    test "destroying a matter deletes its themes" do
      @matter.themes.create!(theme_slug: "housing")

      assert_difference -> { MatterTheme.count }, -1 do
        @matter.destroy!
      end
    end

    test "for_theme scope filters by slug" do
      @matter.themes.create!(theme_slug: "housing")
      other = Matter.create!(legistar_matter_id: 91002, matter_file: "26-901")
      other.themes.create!(theme_slug: "transportation")

      assert_equal [ @matter.id ], MatterTheme.for_theme("housing").pluck(:civic_matter_id)
    end

    test "primary scope returns only rank 1 themes" do
      @matter.themes.create!(theme_slug: "housing", rank: 1)
      @matter.themes.create!(theme_slug: "land_use_zoning", rank: 2)

      assert_equal [ "housing" ], MatterTheme.primary.pluck(:theme_slug)
    end
  end
end

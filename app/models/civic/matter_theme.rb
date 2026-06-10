module Civic
  class MatterTheme < ApplicationRecord
    self.table_name = "civic_matter_themes"

    include BumpsJurisdictionDataVersion

    bumps_jurisdiction_data_version via: :jurisdiction_id_for_data_version

    belongs_to :matter, class_name: "Civic::Matter", foreign_key: :civic_matter_id, inverse_of: :themes
    belongs_to :source_artifact, class_name: "Generated::Artifact", optional: true

    # The valid vocabulary depends on the matter's jurisdiction, so resolve the
    # slug set per record. The proc form keeps the default "is not included in
    # the list" message.
    validates :theme_slug, presence: true,
      inclusion: { in: ->(theme) { ThemeTaxonomy.slugs_for(theme.matter&.civic_jurisdiction) } }
    validates :theme_slug, uniqueness: { scope: :civic_matter_id }

    scope :for_theme, ->(slug) { where(theme_slug: slug) }
    scope :primary, -> { where(rank: 1) }
    scope :by_rank, -> { order(:rank) }

    def label
      ThemeTaxonomy.label_for(theme_slug, matter&.civic_jurisdiction)
    end

    private

    def jurisdiction_id_for_data_version
      matter&.civic_jurisdiction_id
    end
  end
end

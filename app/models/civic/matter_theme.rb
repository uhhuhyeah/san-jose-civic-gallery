module Civic
  class MatterTheme < ApplicationRecord
    self.table_name = "civic_matter_themes"

    belongs_to :matter, class_name: "Civic::Matter", foreign_key: :civic_matter_id, inverse_of: :themes
    belongs_to :source_artifact, class_name: "Generated::Artifact", optional: true

    validates :theme_slug, presence: true, inclusion: { in: ThemeTaxonomy.slugs }
    validates :theme_slug, uniqueness: { scope: :civic_matter_id }

    scope :for_theme, ->(slug) { where(theme_slug: slug) }
    scope :primary, -> { where(rank: 1) }
    scope :by_rank, -> { order(:rank) }

    def label
      ThemeTaxonomy.label_for(theme_slug)
    end
  end
end

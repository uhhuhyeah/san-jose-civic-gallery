class AddRankToCivicMatterThemes < ActiveRecord::Migration[8.1]
  def change
    add_column :civic_matter_themes, :rank, :integer

    # Supports counting each theme's primary (rank 1) matters for the pulse.
    add_index :civic_matter_themes, [ :rank, :theme_slug ], name: "idx_civic_matter_themes_by_rank_theme"
  end
end

class CreateCivicMatterThemes < ActiveRecord::Migration[8.1]
  def change
    create_table :civic_matter_themes do |t|
      t.bigint :civic_matter_id, null: false
      t.string :theme_slug, null: false
      t.float :confidence
      t.bigint :source_artifact_id

      t.timestamps
    end

    add_index :civic_matter_themes, [ :theme_slug, :civic_matter_id ], name: "idx_civic_matter_themes_by_theme"
    add_index :civic_matter_themes, [ :civic_matter_id, :theme_slug ], unique: true, name: "idx_civic_matter_themes_unique_per_matter"
    add_index :civic_matter_themes, :source_artifact_id, name: "index_civic_matter_themes_on_source_artifact_id"

    add_foreign_key :civic_matter_themes, :civic_matters, column: :civic_matter_id
    add_foreign_key :civic_matter_themes, :generated_artifacts, column: :source_artifact_id, on_delete: :nullify
  end
end

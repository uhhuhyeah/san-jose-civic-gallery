class AddSearchableTextToCivicEventsAndMatters < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :civic_events, :searchable_text, :text
    add_index :civic_events,
      "to_tsvector('english', coalesce(searchable_text, ''))",
      using: :gin,
      name: "idx_civic_events_searchable_text",
      algorithm: :concurrently

    add_column :civic_matters, :searchable_text, :text
    add_index :civic_matters,
      "to_tsvector('english', coalesce(searchable_text, ''))",
      using: :gin,
      name: "idx_civic_matters_searchable_text",
      algorithm: :concurrently
  end
end

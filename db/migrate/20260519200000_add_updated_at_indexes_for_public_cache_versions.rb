class AddUpdatedAtIndexesForPublicCacheVersions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLES = %i[
    civic_events
    civic_event_items
    civic_matters
    civic_matter_attachments
    document_extracted_texts
    generated_artifacts
  ].freeze

  def up
    TABLES.each do |table|
      add_index table, :updated_at, algorithm: :concurrently, if_not_exists: true
    end
  end

  def down
    TABLES.each do |table|
      remove_index table, :updated_at, algorithm: :concurrently, if_exists: true
    end
  end
end

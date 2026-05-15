class AddSourceSystemScopingAndProvenance < ActiveRecord::Migration[8.1]
  CIVIC_TABLES = %i[civic_events civic_event_items civic_matters civic_matter_attachments].freeze

  def change
    # Three earlier migration files were edited after their initial run, so
    # envs that migrated before the edits are missing the columns and indexes
    # those edits introduced. Backfill idempotently here.
    add_column :civic_event_items, :source_present, :boolean, null: false, default: true, if_not_exists: true
    add_column :civic_event_items, :source_missing_at, :datetime, if_not_exists: true
    add_index :civic_event_items, [ :civic_event_id, :source_present ],
      name: "idx_civic_event_items_source_presence", if_not_exists: true

    add_column :civic_matter_attachments, :source_present, :boolean, null: false, default: true, if_not_exists: true
    add_column :civic_matter_attachments, :source_missing_at, :datetime, if_not_exists: true
    add_index :civic_matter_attachments, [ :civic_matter_id, :source_present ],
      name: "idx_civic_matter_attachments_source_presence", if_not_exists: true

    add_column :document_extracted_texts, :source_file_checksum_sha256, :string, if_not_exists: true
    if index_name_exists?(:document_extracted_texts, "idx_document_extracted_texts_attachment")
      remove_index :document_extracted_texts,
        column: :civic_matter_attachment_id,
        name: "idx_document_extracted_texts_attachment",
        unique: true
    end
    add_index :document_extracted_texts, [ :civic_matter_attachment_id, :created_at ],
      name: "idx_document_extracted_texts_attachment_history", if_not_exists: true

    CIVIC_TABLES.each do |table|
      add_column table, :source_system, :string, null: false, default: "legistar.sanjose"
      add_reference table, :last_source_snapshot,
        foreign_key: { to_table: :ingestion_source_snapshots, on_delete: :nullify },
        null: true,
        index: true
    end

    add_column :civic_events, :source_present, :boolean, null: false, default: true
    add_column :civic_events, :source_missing_at, :datetime
    add_index :civic_events, [ :source_present ], name: "idx_civic_events_source_presence"

    remove_index :civic_events, column: :legistar_event_id
    add_index :civic_events, [ :source_system, :legistar_event_id ],
      unique: true, name: "idx_civic_events_unique_per_source"

    remove_index :civic_event_items, column: :legistar_event_item_id
    add_index :civic_event_items, [ :source_system, :legistar_event_item_id ],
      unique: true, name: "idx_civic_event_items_unique_per_source"

    remove_index :civic_matters, column: :legistar_matter_id
    add_index :civic_matters, [ :source_system, :legistar_matter_id ],
      unique: true, name: "idx_civic_matters_unique_per_source"

    remove_index :civic_matter_attachments, column: :legistar_matter_attachment_id
    add_index :civic_matter_attachments, [ :source_system, :legistar_matter_attachment_id ],
      unique: true, name: "idx_civic_matter_attachments_unique_per_source"

    add_index :civic_event_items, [ :source_system, :matter_id ],
      name: "idx_civic_event_items_source_system_matter_id"
  end
end

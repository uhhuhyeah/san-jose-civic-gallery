class AddSearchableExtractedTextToMatterAttachments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_reference :civic_matter_attachments,
      :searchable_extracted_text,
      foreign_key: { to_table: :document_extracted_texts },
      index: false

    execute <<~SQL
      UPDATE civic_matter_attachments
      SET searchable_extracted_text_id = latest_extractions.id
      FROM (
        SELECT DISTINCT ON (civic_matter_attachment_id)
          id,
          civic_matter_attachment_id
        FROM document_extracted_texts
        WHERE status = 'ok'
          AND content IS NOT NULL
          AND content <> ''
        ORDER BY civic_matter_attachment_id, created_at DESC, id DESC
      ) AS latest_extractions
      WHERE civic_matter_attachments.id = latest_extractions.civic_matter_attachment_id
    SQL

    add_index :civic_matter_attachments,
      :searchable_extracted_text_id,
      algorithm: :concurrently
  end

  def down
    remove_index :civic_matter_attachments,
      :searchable_extracted_text_id,
      algorithm: :concurrently
    remove_reference :civic_matter_attachments,
      :searchable_extracted_text,
      foreign_key: { to_table: :document_extracted_texts }
  end
end

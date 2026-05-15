class CreateDocumentExtractedTexts < ActiveRecord::Migration[8.1]
  def change
    create_table :document_extracted_texts do |t|
      t.references :civic_matter_attachment, null: false, foreign_key: { to_table: :civic_matter_attachments }
      t.string :extractor_name, null: false
      t.string :extractor_version
      t.datetime :extracted_at
      t.integer :character_count
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.string :source_file_checksum_sha256
      t.text :content

      t.timestamps
    end

    add_index :document_extracted_texts, [ :civic_matter_attachment_id, :created_at ], name: "idx_document_extracted_texts_attachment_history"
  end
end

class AddRemoteValidationFieldsToCivicMatterAttachments < ActiveRecord::Migration[8.1]
  def change
    add_column :civic_matter_attachments, :source_file_final_url, :string
    add_column :civic_matter_attachments, :source_file_etag, :string
    add_column :civic_matter_attachments, :source_file_last_modified_at, :datetime
    add_column :civic_matter_attachments, :source_file_validated_at, :datetime
    add_column :civic_matter_attachments, :source_file_validation_error, :text

    add_index :civic_matter_attachments,
      [ :source_file_validated_at, :source_file_imported_at ],
      name: "idx_civic_matter_attachments_file_validation"
  end
end

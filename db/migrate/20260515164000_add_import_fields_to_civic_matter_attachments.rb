class AddImportFieldsToCivicMatterAttachments < ActiveRecord::Migration[8.1]
  def change
    add_column :civic_matter_attachments, :source_file_imported_at, :datetime
    add_column :civic_matter_attachments, :source_file_checksum_sha256, :string
    add_column :civic_matter_attachments, :source_file_byte_size, :bigint
    add_column :civic_matter_attachments, :source_file_import_error, :text
  end
end

class AddManualImportFieldsToCivicMatterAttachments < ActiveRecord::Migration[8.1]
  def change
    add_column :civic_matter_attachments, :manually_imported_at, :datetime
    add_column :civic_matter_attachments, :manually_imported_by, :string
    add_column :civic_matter_attachments, :manual_import_reason, :text
  end
end

class CreateCivicMatterAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :civic_matter_attachments do |t|
      t.references :civic_matter, null: false, foreign_key: { to_table: :civic_matters }
      t.bigint :legistar_matter_attachment_id, null: false
      t.string :name, null: false
      t.string :hyperlink
      t.string :file_name
      t.string :matter_version
      t.boolean :is_hyperlink
      t.boolean :is_supporting_document
      t.boolean :show_on_internet_page
      t.boolean :is_minute_order
      t.boolean :is_board_letter
      t.text :description
      t.boolean :print_with_reports
      t.integer :sort_order
      t.datetime :source_last_modified_at
      t.datetime :last_synced_at
      t.string :raw_source_digest

      t.timestamps
    end

    add_index :civic_matter_attachments, :legistar_matter_attachment_id, unique: true
    add_index :civic_matter_attachments, [:civic_matter_id, :sort_order], name: "idx_civic_matter_attachments_order"
  end
end

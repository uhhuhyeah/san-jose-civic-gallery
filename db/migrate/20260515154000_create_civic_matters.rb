class CreateCivicMatters < ActiveRecord::Migration[8.1]
  def change
    create_table :civic_matters do |t|
      t.bigint :legistar_matter_id, null: false
      t.string :matter_file, null: false
      t.string :body_name
      t.text :title
      t.text :name
      t.string :matter_type_name
      t.string :matter_status_name
      t.string :requester
      t.date :intro_date
      t.date :agenda_date
      t.date :passed_date
      t.date :enactment_date
      t.string :enactment_number
      t.string :version
      t.text :notes
      t.datetime :source_last_modified_at
      t.datetime :last_synced_at
      t.string :raw_source_digest

      t.timestamps
    end

    add_index :civic_matters, :legistar_matter_id, unique: true
    add_index :civic_matters, :matter_file
  end
end

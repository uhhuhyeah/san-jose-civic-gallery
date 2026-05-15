class CreateCivicEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :civic_events do |t|
      t.bigint :legistar_event_id, null: false
      t.string :body_name
      t.string :title
      t.date :event_date, null: false
      t.string :event_time
      t.string :location_name
      t.string :agenda_status_name
      t.string :minutes_status_name
      t.string :in_site_url
      t.string :agenda_file_uri
      t.string :minutes_file_uri
      t.datetime :source_last_modified_at
      t.datetime :last_synced_at
      t.string :raw_source_digest

      t.timestamps
    end

    add_index :civic_events, :legistar_event_id, unique: true
    add_index :civic_events, :event_date
  end
end

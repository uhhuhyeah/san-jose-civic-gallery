class CreateCivicEventItems < ActiveRecord::Migration[8.1]
  def change
    create_table :civic_event_items do |t|
      t.references :civic_event, null: false, foreign_key: { to_table: :civic_events }
      t.bigint :legistar_event_item_id, null: false
      t.integer :agenda_sequence
      t.integer :minutes_sequence
      t.string :agenda_number
      t.text :title
      t.text :agenda_note
      t.text :minutes_note
      t.string :action_name
      t.text :action_text
      t.string :passed_flag_name
      t.integer :roll_call_flag
      t.integer :consent
      t.string :tally
      t.bigint :matter_id
      t.string :matter_file
      t.text :matter_name
      t.string :matter_type
      t.string :matter_status
      t.boolean :source_present, null: false, default: true
      t.datetime :source_missing_at
      t.datetime :source_last_modified_at
      t.datetime :last_synced_at
      t.string :raw_source_digest

      t.timestamps
    end

    add_index :civic_event_items, :legistar_event_item_id, unique: true
    add_index :civic_event_items, [ :civic_event_id, :agenda_sequence ], name: "idx_civic_event_items_agenda_order"
    add_index :civic_event_items, [ :civic_event_id, :source_present ], name: "idx_civic_event_items_source_presence"
  end
end

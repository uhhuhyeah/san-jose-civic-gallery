# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_15_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "civic_event_items", force: :cascade do |t|
    t.string "action_name"
    t.text "action_text"
    t.text "agenda_note"
    t.string "agenda_number"
    t.integer "agenda_sequence"
    t.bigint "civic_event_id", null: false
    t.integer "consent"
    t.datetime "created_at", null: false
    t.datetime "last_synced_at"
    t.bigint "legistar_event_item_id", null: false
    t.string "matter_file"
    t.bigint "matter_id"
    t.text "matter_name"
    t.string "matter_status"
    t.string "matter_type"
    t.text "minutes_note"
    t.integer "minutes_sequence"
    t.string "passed_flag_name"
    t.string "raw_source_digest"
    t.integer "roll_call_flag"
    t.datetime "source_last_modified_at"
    t.string "tally"
    t.text "title"
    t.datetime "updated_at", null: false
    t.index ["civic_event_id", "agenda_sequence"], name: "idx_civic_event_items_agenda_order"
    t.index ["civic_event_id"], name: "index_civic_event_items_on_civic_event_id"
    t.index ["legistar_event_item_id"], name: "index_civic_event_items_on_legistar_event_item_id", unique: true
  end

  create_table "civic_events", force: :cascade do |t|
    t.string "agenda_file_uri"
    t.string "agenda_status_name"
    t.string "body_name"
    t.datetime "created_at", null: false
    t.date "event_date", null: false
    t.string "event_time"
    t.string "in_site_url"
    t.datetime "last_synced_at"
    t.bigint "legistar_event_id", null: false
    t.string "location_name"
    t.string "minutes_file_uri"
    t.string "minutes_status_name"
    t.string "raw_source_digest"
    t.datetime "source_last_modified_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["event_date"], name: "index_civic_events_on_event_date"
    t.index ["legistar_event_id"], name: "index_civic_events_on_legistar_event_id", unique: true
  end

  create_table "ingestion_source_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fetched_at", null: false
    t.integer "http_status", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "request_url", null: false
    t.string "resource_type", null: false
    t.string "response_sha256", null: false
    t.string "source_id", null: false
    t.string "source_system", null: false
    t.datetime "updated_at", null: false
    t.index ["fetched_at"], name: "index_ingestion_source_snapshots_on_fetched_at"
    t.index ["source_system", "resource_type", "source_id"], name: "idx_source_snapshots_identity"
  end

  add_foreign_key "civic_event_items", "civic_events"
end

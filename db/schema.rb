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

ActiveRecord::Schema[8.1].define(version: 2026_07_03_173624) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "civic_event_items", force: :cascade do |t|
    t.string "action_name"
    t.text "action_text"
    t.text "agenda_note"
    t.string "agenda_number"
    t.integer "agenda_sequence"
    t.bigint "civic_event_id", null: false
    t.bigint "civic_jurisdiction_id", null: false
    t.bigint "civic_matter_id"
    t.integer "consent"
    t.datetime "created_at", null: false
    t.bigint "last_source_snapshot_id"
    t.datetime "last_synced_at"
    t.bigint "legistar_event_item_id"
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
    t.string "source_event_item_id", null: false
    t.datetime "source_last_modified_at"
    t.datetime "source_missing_at"
    t.boolean "source_present", default: true, null: false
    t.string "source_system", default: "legistar.sanjose", null: false
    t.string "tally"
    t.text "title"
    t.datetime "updated_at", null: false
    t.index ["civic_event_id", "agenda_sequence"], name: "idx_civic_event_items_agenda_order"
    t.index ["civic_event_id", "source_present"], name: "idx_civic_event_items_source_presence"
    t.index ["civic_event_id"], name: "index_civic_event_items_on_civic_event_id"
    t.index ["civic_jurisdiction_id"], name: "index_civic_event_items_on_civic_jurisdiction_id"
    t.index ["civic_matter_id"], name: "index_civic_event_items_on_civic_matter_id"
    t.index ["last_source_snapshot_id"], name: "index_civic_event_items_on_last_source_snapshot_id"
    t.index ["source_system", "legistar_event_item_id"], name: "idx_civic_event_items_unique_per_source", unique: true
    t.index ["source_system", "matter_id"], name: "idx_civic_event_items_source_system_matter_id"
    t.index ["source_system", "source_event_item_id"], name: "idx_civic_event_items_unique_source_id", unique: true
    t.index ["updated_at"], name: "index_civic_event_items_on_updated_at"
  end

  create_table "civic_events", force: :cascade do |t|
    t.string "agenda_file_uri"
    t.string "agenda_status_name"
    t.string "body_name"
    t.bigint "civic_jurisdiction_id", null: false
    t.datetime "created_at", null: false
    t.date "event_date", null: false
    t.string "event_time"
    t.string "in_site_url"
    t.bigint "last_source_snapshot_id"
    t.datetime "last_synced_at"
    t.bigint "legistar_event_id"
    t.string "location_name"
    t.string "minutes_file_uri"
    t.string "minutes_status_name"
    t.string "raw_source_digest"
    t.string "source_event_id", null: false
    t.datetime "source_last_modified_at"
    t.string "source_meeting_type"
    t.datetime "source_missing_at"
    t.boolean "source_present", default: true, null: false
    t.string "source_system", default: "legistar.sanjose", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["civic_jurisdiction_id", "body_name", "event_date"], name: "idx_civic_events_jurisdiction_body_date"
    t.index ["civic_jurisdiction_id"], name: "index_civic_events_on_civic_jurisdiction_id"
    t.index ["event_date"], name: "index_civic_events_on_event_date"
    t.index ["last_source_snapshot_id"], name: "index_civic_events_on_last_source_snapshot_id"
    t.index ["source_present"], name: "idx_civic_events_source_presence"
    t.index ["source_system", "legistar_event_id"], name: "idx_civic_events_unique_per_source", unique: true
    t.index ["source_system", "source_event_id"], name: "idx_civic_events_unique_source_id", unique: true
    t.index ["updated_at"], name: "index_civic_events_on_updated_at"
  end

  create_table "civic_jurisdictions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "data_updated_at"
    t.string "kind", null: false
    t.string "name", null: false
    t.string "primary_host", null: false
    t.string "slug", null: false
    t.string "source_system_default"
    t.datetime "updated_at", null: false
    t.index ["primary_host"], name: "index_civic_jurisdictions_on_primary_host", unique: true
    t.index ["slug"], name: "index_civic_jurisdictions_on_slug", unique: true
    t.index ["source_system_default"], name: "idx_civic_jurisdictions_source_system_default", unique: true, where: "(source_system_default IS NOT NULL)"
  end

  create_table "civic_matter_attachments", force: :cascade do |t|
    t.bigint "civic_jurisdiction_id", null: false
    t.bigint "civic_matter_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "file_name"
    t.string "hyperlink"
    t.boolean "is_board_letter"
    t.boolean "is_hyperlink"
    t.boolean "is_minute_order"
    t.boolean "is_supporting_document"
    t.bigint "last_source_snapshot_id"
    t.datetime "last_synced_at"
    t.bigint "legistar_matter_attachment_id"
    t.text "manual_import_reason"
    t.datetime "manually_imported_at"
    t.string "manually_imported_by"
    t.string "matter_version"
    t.string "name", null: false
    t.boolean "print_with_reports"
    t.string "raw_source_digest"
    t.boolean "show_on_internet_page"
    t.integer "sort_order"
    t.string "source_attachment_id", null: false
    t.bigint "source_file_byte_size"
    t.string "source_file_checksum_sha256"
    t.string "source_file_etag"
    t.string "source_file_final_url"
    t.text "source_file_import_error"
    t.datetime "source_file_imported_at"
    t.datetime "source_file_last_modified_at"
    t.datetime "source_file_validated_at"
    t.text "source_file_validation_error"
    t.datetime "source_last_modified_at"
    t.datetime "source_missing_at"
    t.boolean "source_present", default: true, null: false
    t.string "source_system", default: "legistar.sanjose", null: false
    t.datetime "updated_at", null: false
    t.index ["civic_jurisdiction_id"], name: "index_civic_matter_attachments_on_civic_jurisdiction_id"
    t.index ["civic_matter_id", "sort_order"], name: "idx_civic_matter_attachments_order"
    t.index ["civic_matter_id", "source_present"], name: "idx_civic_matter_attachments_source_presence"
    t.index ["civic_matter_id"], name: "index_civic_matter_attachments_on_civic_matter_id"
    t.index ["last_source_snapshot_id"], name: "index_civic_matter_attachments_on_last_source_snapshot_id"
    t.index ["source_file_validated_at", "source_file_imported_at"], name: "idx_civic_matter_attachments_file_validation"
    t.index ["source_system", "legistar_matter_attachment_id"], name: "idx_civic_matter_attachments_unique_per_source", unique: true
    t.index ["source_system", "source_attachment_id"], name: "idx_civic_matter_attachments_unique_source_id", unique: true
    t.index ["updated_at"], name: "index_civic_matter_attachments_on_updated_at"
  end

  create_table "civic_matter_themes", force: :cascade do |t|
    t.bigint "civic_matter_id", null: false
    t.float "confidence"
    t.datetime "created_at", null: false
    t.integer "rank"
    t.bigint "source_artifact_id"
    t.string "theme_slug", null: false
    t.datetime "updated_at", null: false
    t.index ["civic_matter_id", "theme_slug"], name: "idx_civic_matter_themes_unique_per_matter", unique: true
    t.index ["rank", "theme_slug"], name: "idx_civic_matter_themes_by_rank_theme"
    t.index ["source_artifact_id"], name: "index_civic_matter_themes_on_source_artifact_id"
    t.index ["theme_slug", "civic_matter_id"], name: "idx_civic_matter_themes_by_theme"
  end

  create_table "civic_matters", force: :cascade do |t|
    t.date "agenda_date"
    t.string "body_name"
    t.bigint "civic_jurisdiction_id", null: false
    t.datetime "created_at", null: false
    t.date "enactment_date"
    t.string "enactment_number"
    t.date "intro_date"
    t.bigint "last_source_snapshot_id"
    t.datetime "last_synced_at"
    t.bigint "legistar_matter_id"
    t.string "matter_file", null: false
    t.string "matter_status_name"
    t.string "matter_type_name"
    t.text "name"
    t.text "notes"
    t.date "passed_date"
    t.string "raw_source_digest"
    t.string "requester"
    t.datetime "source_last_modified_at"
    t.string "source_matter_id", null: false
    t.string "source_system", default: "legistar.sanjose", null: false
    t.text "title"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["civic_jurisdiction_id"], name: "index_civic_matters_on_civic_jurisdiction_id"
    t.index ["last_source_snapshot_id"], name: "index_civic_matters_on_last_source_snapshot_id"
    t.index ["matter_file"], name: "index_civic_matters_on_matter_file"
    t.index ["source_system", "legistar_matter_id"], name: "idx_civic_matters_unique_per_source", unique: true
    t.index ["source_system", "source_matter_id"], name: "idx_civic_matters_unique_source_id", unique: true
    t.index ["updated_at"], name: "index_civic_matters_on_updated_at"
  end

  create_table "civic_roundup_periods", force: :cascade do |t|
    t.bigint "civic_jurisdiction_id", null: false
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.date "period_end", null: false
    t.date "period_start", null: false
    t.datetime "updated_at", null: false
    t.index ["civic_jurisdiction_id", "period_start", "period_end"], name: "idx_civic_roundup_periods_unique", unique: true
    t.index ["civic_jurisdiction_id"], name: "index_civic_roundup_periods_on_civic_jurisdiction_id"
  end

  create_table "data_health_job_status_snapshots", force: :cascade do |t|
    t.datetime "captured_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.integer "failed_jobs_last_24_hours", default: 0, null: false
    t.integer "failed_jobs_last_hour", default: 0, null: false
    t.index ["captured_at"], name: "index_data_health_job_status_snapshots_on_captured_at"
  end

  create_table "document_extracted_texts", force: :cascade do |t|
    t.integer "character_count"
    t.bigint "civic_matter_attachment_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "extracted_at"
    t.string "extractor_name", null: false
    t.string "extractor_version"
    t.string "source_file_checksum_sha256"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index "to_tsvector('english'::regconfig, COALESCE(content, ''::text))", name: "idx_document_extracted_texts_content_search", where: "((status)::text = 'ok'::text)", using: :gin
    t.index ["civic_matter_attachment_id", "created_at"], name: "idx_document_extracted_texts_attachment_history"
    t.index ["civic_matter_attachment_id"], name: "index_document_extracted_texts_on_civic_matter_attachment_id"
    t.index ["updated_at"], name: "index_document_extracted_texts_on_updated_at"
  end

  create_table "generated_artifacts", force: :cascade do |t|
    t.jsonb "content", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "generated_at"
    t.jsonb "input_metadata", default: {}, null: false
    t.string "input_sha256", null: false
    t.string "kind", null: false
    t.string "model_identifier", null: false
    t.string "prompt_version", null: false
    t.bigint "source_artifact_id"
    t.string "source_artifact_type"
    t.string "status", default: "pending", null: false
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.jsonb "usage_metadata", default: {}, null: false
    t.index ["source_artifact_type", "source_artifact_id"], name: "idx_generated_artifacts_source"
    t.index ["target_type", "target_id", "kind", "model_identifier", "prompt_version", "input_sha256"], name: "idx_generated_artifacts_idempotency", unique: true
    t.index ["target_type", "target_id"], name: "idx_generated_artifacts_target"
    t.index ["updated_at"], name: "index_generated_artifacts_on_updated_at"
  end

  create_table "ingestion_source_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "fetch_count", default: 1, null: false
    t.datetime "fetched_at", null: false
    t.integer "http_status", null: false
    t.datetime "last_fetched_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "request_url", null: false
    t.string "resource_type", null: false
    t.string "response_sha256", null: false
    t.string "source_id", null: false
    t.string "source_system", null: false
    t.datetime "updated_at", null: false
    t.index ["fetched_at"], name: "index_ingestion_source_snapshots_on_fetched_at"
    t.index ["source_system", "resource_type", "source_id", "response_sha256"], name: "idx_source_snapshots_unique_payload_version", unique: true
    t.index ["source_system", "resource_type", "source_id"], name: "idx_source_snapshots_identity"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "civic_event_items", "civic_events"
  add_foreign_key "civic_event_items", "civic_jurisdictions"
  add_foreign_key "civic_event_items", "civic_matters"
  add_foreign_key "civic_event_items", "ingestion_source_snapshots", column: "last_source_snapshot_id", on_delete: :nullify
  add_foreign_key "civic_events", "civic_jurisdictions"
  add_foreign_key "civic_events", "ingestion_source_snapshots", column: "last_source_snapshot_id", on_delete: :nullify
  add_foreign_key "civic_matter_attachments", "civic_jurisdictions"
  add_foreign_key "civic_matter_attachments", "civic_matters"
  add_foreign_key "civic_matter_attachments", "ingestion_source_snapshots", column: "last_source_snapshot_id", on_delete: :nullify
  add_foreign_key "civic_matter_themes", "civic_matters"
  add_foreign_key "civic_matter_themes", "generated_artifacts", column: "source_artifact_id", on_delete: :nullify
  add_foreign_key "civic_matters", "civic_jurisdictions"
  add_foreign_key "civic_matters", "ingestion_source_snapshots", column: "last_source_snapshot_id", on_delete: :nullify
  add_foreign_key "civic_roundup_periods", "civic_jurisdictions"
  add_foreign_key "document_extracted_texts", "civic_matter_attachments"
end

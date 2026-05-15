class CreateIngestionSourceSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :ingestion_source_snapshots do |t|
      t.string :source_system, null: false
      t.string :resource_type, null: false
      t.string :source_id, null: false
      t.string :request_url, null: false
      t.datetime :fetched_at, null: false
      t.integer :http_status, null: false
      t.string :response_sha256, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :ingestion_source_snapshots, [:source_system, :resource_type, :source_id], name: "idx_source_snapshots_identity"
    add_index :ingestion_source_snapshots, :fetched_at
  end
end

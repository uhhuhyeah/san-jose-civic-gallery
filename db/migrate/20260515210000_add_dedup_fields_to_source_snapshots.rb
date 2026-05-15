class AddDedupFieldsToSourceSnapshots < ActiveRecord::Migration[8.1]
  def up
    add_column :ingestion_source_snapshots, :last_fetched_at, :datetime
    add_column :ingestion_source_snapshots, :fetch_count, :integer, null: false, default: 1

    execute "UPDATE ingestion_source_snapshots SET last_fetched_at = fetched_at WHERE last_fetched_at IS NULL"
    change_column_null :ingestion_source_snapshots, :last_fetched_at, false
  end

  def down
    remove_column :ingestion_source_snapshots, :fetch_count
    remove_column :ingestion_source_snapshots, :last_fetched_at
  end
end

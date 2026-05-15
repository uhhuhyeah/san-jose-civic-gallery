class AddUniquePayloadVersionIndexToSourceSnapshots < ActiveRecord::Migration[8.1]
  def up
    deduplicate_existing_versions

    add_index :ingestion_source_snapshots,
      [ :source_system, :resource_type, :source_id, :response_sha256 ],
      unique: true,
      name: "idx_source_snapshots_unique_payload_version",
      if_not_exists: true
  end

  def down
    remove_index :ingestion_source_snapshots,
      name: "idx_source_snapshots_unique_payload_version",
      if_exists: true
  end

  private

  def deduplicate_existing_versions
    execute <<~SQL.squish
      WITH duplicate_groups AS (
        SELECT
          source_system,
          resource_type,
          source_id,
          response_sha256,
          MIN(id) AS keeper_id,
          MIN(fetched_at) AS first_fetched_at,
          MAX(last_fetched_at) AS latest_fetched_at,
          SUM(fetch_count) AS total_fetch_count,
          COUNT(*) AS row_count
        FROM ingestion_source_snapshots
        GROUP BY source_system, resource_type, source_id, response_sha256
        HAVING COUNT(*) > 1
      ),
      updated_keepers AS (
        UPDATE ingestion_source_snapshots snapshots
        SET
          fetched_at = duplicate_groups.first_fetched_at,
          last_fetched_at = duplicate_groups.latest_fetched_at,
          fetch_count = duplicate_groups.total_fetch_count,
          updated_at = CURRENT_TIMESTAMP
        FROM duplicate_groups
        WHERE snapshots.id = duplicate_groups.keeper_id
        RETURNING snapshots.id
      )
      DELETE FROM ingestion_source_snapshots snapshots
      USING duplicate_groups
      WHERE snapshots.source_system = duplicate_groups.source_system
        AND snapshots.resource_type = duplicate_groups.resource_type
        AND snapshots.source_id = duplicate_groups.source_id
        AND snapshots.response_sha256 = duplicate_groups.response_sha256
        AND snapshots.id <> duplicate_groups.keeper_id
    SQL
  end
end

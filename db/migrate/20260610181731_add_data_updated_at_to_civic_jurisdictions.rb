# Single per-jurisdiction timestamp that advances whenever any public-facing
# record in that jurisdiction changes (see BumpsJurisdictionDataVersion).
# Public::CacheVersion derives ETags from it instead of running COUNT/MAX
# aggregate queries on every request. Nullable: a jurisdiction with no bump yet
# falls back to its own updated_at.
class AddDataUpdatedAtToCivicJurisdictions < ActiveRecord::Migration[8.1]
  def change
    add_column :civic_jurisdictions, :data_updated_at, :datetime
  end
end

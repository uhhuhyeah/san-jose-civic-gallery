class TruncateSolidCacheEntries < ActiveRecord::Migration[8.0]
  def up
    execute "TRUNCATE TABLE solid_cache_entries" if table_exists?(:solid_cache_entries)
  end

  def down
    # Data cannot be restored
  end
end

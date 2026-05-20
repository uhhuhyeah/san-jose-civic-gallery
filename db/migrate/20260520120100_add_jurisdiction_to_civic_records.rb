class AddJurisdictionToCivicRecords < ActiveRecord::Migration[8.1]
  TABLES = %i[civic_events civic_event_items civic_matters civic_matter_attachments].freeze

  def up
    TABLES.each do |table|
      add_reference table, :civic_jurisdiction, null: true, index: true, foreign_key: { to_table: :civic_jurisdictions }
    end

    # Ensure the canonical jurisdictions exist so existing rows can be
    # backfilled on deploy. schema:load does not run migration bodies, so
    # fresh databases get these rows from db/seeds.rb instead. Values are
    # frozen here on purpose; ongoing definitions live in
    # Civic::Jurisdiction.seed_defaults!.
    execute <<~SQL.squish
      INSERT INTO civic_jurisdictions
        (slug, name, kind, primary_host, source_system_default, created_at, updated_at)
      VALUES
        ('sanjose', 'San Jose City Government', 'city',
          'sanjose.civicgallery.org', 'legistar.sanjose', now(), now()),
        ('sjusd', 'San Jose Unified School District', 'school_district',
          'sjusd.civicgallery.org', 'simbli.sjusd', now(), now())
      ON CONFLICT (slug) DO NOTHING;
    SQL

    sanjose_id = select_value("SELECT id FROM civic_jurisdictions WHERE slug = 'sanjose'")
    raise "sanjose jurisdiction missing; cannot backfill" if sanjose_id.blank?

    # All existing records predate SJUSD and belong to San Jose.
    TABLES.each do |table|
      execute "UPDATE #{table} SET civic_jurisdiction_id = #{Integer(sanjose_id)} WHERE civic_jurisdiction_id IS NULL"
      change_column_null table, :civic_jurisdiction_id, false
    end
  end

  def down
    TABLES.each do |table|
      remove_reference table, :civic_jurisdiction, foreign_key: { to_table: :civic_jurisdictions }, index: true
    end
  end
end

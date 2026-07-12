# The county jurisdiction row must exist in production before the recurring
# IQM2 discovery job runs. Unlike sanjose/sjusd (inserted by the original
# add_jurisdiction_to_civic_records migration), the county was added only to
# Civic::Jurisdiction::DEFAULTS / seed_defaults!, and deploys run db:migrate but
# not db:seed. This inserts the row idempotently so a normal deploy is enough,
# with no manual seed step at cutover. Values are a frozen copy of DEFAULTS so a
# later DEFAULTS edit does not retroactively change what this migration did.
class SeedSantaClaraCountyJurisdiction < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      INSERT INTO civic_jurisdictions
        (slug, name, kind, primary_host, source_system_default, created_at, updated_at)
      VALUES
        ('santaclaracounty', 'County of Santa Clara', 'county',
         'santaclaracounty.civicgallery.org', 'iqm2.sccgov', now(), now())
      ON CONFLICT (slug) DO NOTHING
    SQL
  end

  def down
    execute("DELETE FROM civic_jurisdictions WHERE slug = 'santaclaracounty'")
  end
end

class CreateCivicJurisdictions < ActiveRecord::Migration[8.1]
  def change
    create_table :civic_jurisdictions do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.string :primary_host, null: false
      t.string :source_system_default

      t.timestamps
    end

    add_index :civic_jurisdictions, :slug, unique: true
    add_index :civic_jurisdictions, :primary_host, unique: true
    add_index :civic_jurisdictions, :source_system_default, unique: true, where: "source_system_default IS NOT NULL", name: "idx_civic_jurisdictions_source_system_default"
  end
end

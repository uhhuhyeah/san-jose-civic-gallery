class CreateCivicRoundupPeriods < ActiveRecord::Migration[8.1]
  def change
    create_table :civic_roundup_periods do |t|
      t.bigint :civic_jurisdiction_id, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :label, null: false

      t.timestamps
    end

    add_index :civic_roundup_periods, [ :civic_jurisdiction_id, :period_start, :period_end ], unique: true, name: "idx_civic_roundup_periods_unique"
    add_index :civic_roundup_periods, :civic_jurisdiction_id, name: "index_civic_roundup_periods_on_civic_jurisdiction_id"

    add_foreign_key :civic_roundup_periods, :civic_jurisdictions, column: :civic_jurisdiction_id
  end
end

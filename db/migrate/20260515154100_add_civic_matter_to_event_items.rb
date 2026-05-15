class AddCivicMatterToEventItems < ActiveRecord::Migration[8.1]
  def change
    add_reference :civic_event_items, :civic_matter, foreign_key: { to_table: :civic_matters }
  end
end

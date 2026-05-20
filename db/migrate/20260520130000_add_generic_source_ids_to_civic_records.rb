class AddGenericSourceIdsToCivicRecords < ActiveRecord::Migration[8.1]
  # table => [generic source id column, legacy Legistar column]
  MAPPING = {
    civic_events: %i[source_event_id legistar_event_id],
    civic_event_items: %i[source_event_item_id legistar_event_item_id],
    civic_matters: %i[source_matter_id legistar_matter_id],
    civic_matter_attachments: %i[source_attachment_id legistar_matter_attachment_id]
  }.freeze

  def up
    MAPPING.each do |table, (generic, legacy)|
      add_column table, generic, :string

      # Existing rows are all Legistar/San Jose; their stable id is the
      # Legistar id as text.
      execute "UPDATE #{table} SET #{generic} = #{legacy}::text WHERE #{generic} IS NULL"
      change_column_null table, generic, false

      add_index table, [ :source_system, generic ], unique: true, name: "idx_#{table}_unique_source_id"

      # Legistar ids become optional so non-Legistar sources (Simbli) can be
      # written without them. The legacy columns and their indexes stay until
      # all call sites move off them.
      change_column_null table, legacy, true
    end
  end

  def down
    MAPPING.each do |table, (generic, legacy)|
      change_column_null table, legacy, false
      remove_index table, name: "idx_#{table}_unique_source_id"
      remove_column table, generic
    end
  end
end

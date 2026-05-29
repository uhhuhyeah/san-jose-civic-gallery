class AddAdjacencyIndexToCivicEvents < ActiveRecord::Migration[8.0]
  # The meeting detail page issues two related queries:
  #
  #   • adjacent meeting: WHERE civic_jurisdiction_id = ? AND body_name = ?
  #     AND source_present = true AND event_date <range> ORDER BY event_date
  #   • body meeting count: WHERE civic_jurisdiction_id = ? AND body_name = ?
  #     AND source_present = true
  #
  # Existing schema indexes civic_jurisdiction_id and event_date independently,
  # which forces a bitmap scan or a single-column index lookup + filter. A
  # composite covers both queries with one index seek and keeps body_name
  # partitioning effective. Adding `source_present` would further narrow but
  # most events are source_present, so the marginal benefit is small.
  def change
    add_index :civic_events,
              [ :civic_jurisdiction_id, :body_name, :event_date ],
              name: "idx_civic_events_jurisdiction_body_date",
              algorithm: :concurrently
  end

  disable_ddl_transaction!
end

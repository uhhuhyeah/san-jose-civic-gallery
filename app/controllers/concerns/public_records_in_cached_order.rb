module PublicRecordsInCachedOrder
  extend ActiveSupport::Concern

  private

  def records_in_cached_order(ids, scope)
    records_by_id = scope.where(id: ids).index_by(&:id)
    ids.filter_map { |id| records_by_id[id] }
  end
end

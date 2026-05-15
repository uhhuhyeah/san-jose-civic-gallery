module Ingestion
  class SourceSnapshot < ApplicationRecord
    self.table_name = "ingestion_source_snapshots"

    validates :source_system, :resource_type, :source_id, :request_url, :fetched_at, :last_fetched_at, :http_status, :response_sha256, presence: true
    validates :fetch_count, numericality: { only_integer: true, greater_than: 0 }
  end
end

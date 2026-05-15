module Ingestion
  class SourceSnapshot < ApplicationRecord
    self.table_name = "ingestion_source_snapshots"

    validates :source_system, :resource_type, :source_id, :request_url, :fetched_at, :http_status, :response_sha256, presence: true
  end
end

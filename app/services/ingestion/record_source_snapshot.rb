module Ingestion
  class RecordSourceSnapshot
    def self.call(source_system:, resource_type:, source_id:, request_url:, fetched_at:, http_status:, response_sha256:, payload:)
      identity = {
        source_system: source_system,
        resource_type: resource_type,
        source_id: source_id
      }

      latest = SourceSnapshot.where(identity).order(:fetched_at, :id).last

      if latest && latest.response_sha256 == response_sha256
        SourceSnapshot.where(id: latest.id).update_all(
          last_fetched_at: fetched_at,
          fetch_count: latest.fetch_count + 1,
          updated_at: Time.current
        )
        latest.reload
      else
        SourceSnapshot.create!(
          **identity,
          request_url: request_url,
          fetched_at: fetched_at,
          last_fetched_at: fetched_at,
          fetch_count: 1,
          http_status: http_status,
          response_sha256: response_sha256,
          payload: payload
        )
      end
    end
  end
end

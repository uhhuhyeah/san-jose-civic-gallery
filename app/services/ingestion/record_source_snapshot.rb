module Ingestion
  class RecordSourceSnapshot
    def self.call(source_system:, resource_type:, source_id:, request_url:, fetched_at:, http_status:, response_sha256:, payload:)
      attributes = {
        source_system: source_system,
        resource_type: resource_type,
        source_id: source_id,
        response_sha256: response_sha256
      }

      existing = bump_existing!(attributes:, fetched_at:)
      return existing if existing

      begin
        SourceSnapshot.create!(
          **attributes,
          request_url: request_url,
          fetched_at: fetched_at,
          last_fetched_at: fetched_at,
          fetch_count: 1,
          http_status: http_status,
          payload: payload
        )
      rescue ActiveRecord::RecordNotUnique
        bump_existing!(attributes:, fetched_at:)
      end
    end

    def self.bump_existing!(attributes:, fetched_at:)
      updated_count = SourceSnapshot.where(attributes).update_all(
        [
          "last_fetched_at = ?, fetch_count = fetch_count + 1, updated_at = ?",
          fetched_at,
          Time.current
        ]
      )
      return nil if updated_count.zero?

      SourceSnapshot.find_by!(attributes)
    end
    private_class_method :bump_existing!
  end
end

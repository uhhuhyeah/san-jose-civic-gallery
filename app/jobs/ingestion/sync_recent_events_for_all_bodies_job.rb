require "net/http"
require "json"

module Ingestion
  # Fans out per-body Ingestion::SyncRecentEventsJob calls across every
  # active Legistar body. Used by the recurring scheduler so a single
  # entry in config/recurring.yml covers the full set of bodies the
  # jurisdiction exposes today, picking up newly added bodies automatically.
  class SyncRecentEventsForAllBodiesJob < ApplicationJob
    queue_as :default

    BODIES_URL = "https://webapi.legistar.com/v1/sanjose/Bodies".freeze

    # body_names is exposed for tests; production callers omit it and let
    # the job fetch the live list from Legistar.
    def perform(limit: 10, body_names: nil)
      bodies = body_names || fetch_active_body_names
      bodies.each do |body|
        SyncRecentEventsJob.perform_later(limit: limit, body_name: body)
      end
      Rails.logger.info(
        "Ingestion::SyncRecentEventsForAllBodiesJob enqueued #{bodies.size} per-body syncs (limit=#{limit})"
      )
    end

    private

    def fetch_active_body_names
      uri = URI(BODIES_URL)
      response = Net::HTTP.get_response(uri)
      status = response.code.to_i
      unless status == 200
        # Reuse the Legistar error hierarchy so ApplicationJob retries 5xx
        # (the /Bodies endpoint is the same upstream) and lets 4xx fail fast.
        raise Legistar::Client.error_for(status, uri.to_s)
      end
      JSON.parse(response.body)
        .select { |body| body["BodyActiveFlag"] == 1 }
        .map { |body| body["BodyName"] }
    end
  end
end

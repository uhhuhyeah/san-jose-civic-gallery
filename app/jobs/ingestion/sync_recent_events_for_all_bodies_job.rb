module Ingestion
  # Fans out per-body Ingestion::SyncRecentEventsJob calls across every
  # active Legistar body. Used by the recurring scheduler so a single
  # entry in config/recurring.yml covers the full set of bodies the
  # jurisdiction exposes today, picking up newly added bodies automatically.
  #
  # Caches the active body-name list for 1 hour. If the live Legistar fetch
  # fails, the last cached list is used and the degraded path is logged,
  # rather than syncing nothing for the entire tick.
  class SyncRecentEventsForAllBodiesJob < ApplicationJob
    queue_as :default

    CACHE_KEY = "ingestion/sync_recent_events_for_all_bodies/active_body_names"
    CACHE_TTL = 1.hour

    # body_names is exposed for tests; production callers omit it and let
    # the job fetch the live list from Legistar.
    # cache is exposed for tests to inject a MemoryStore; production uses
    # the environment-configured Rails.cache (Solid Cache in production).
    def perform(limit: 10, body_names: nil, cache: Rails.cache)
      bodies = body_names || fetch_active_body_names(cache:)
      bodies.each do |body|
        SyncRecentEventsJob.perform_later(limit: limit, body_name: body)
      end
      Rails.logger.info(
        "Ingestion::SyncRecentEventsForAllBodiesJob enqueued #{bodies.size} per-body syncs (limit=#{limit})"
      )
    end

    private

    def fetch_active_body_names(cache: Rails.cache)
      response = client.bodies
      unless response[:status] == 200
        raise "Legistar /Bodies returned HTTP #{response[:status]}"
      end

      names = response[:payload]
        .select { |body| body["BodyActiveFlag"] == 1 }
        .map { |body| body["BodyName"] }

      cache.write(CACHE_KEY, names, expires_in: CACHE_TTL)
      names
    rescue Net::OpenTimeout, Net::ReadTimeout,
           Errno::ECONNRESET, SocketError,
           RuntimeError => e
      cached = cache.read(CACHE_KEY)
      if cached
        Rails.logger.warn(
          "Ingestion::SyncRecentEventsForAllBodiesJob: Legistar /Bodies fetch failed " \
          "(#{e.message}), using #{cached.size} cached body names"
        )
        cached
      else
        raise
      end
    end

    def client
      @client ||= Legistar::Client.new
    end
  end
end

require "test_helper"

module Ingestion
  class SyncRecentEventsForAllBodiesJobTest < ActiveJob::TestCase
    setup do
      clear_enqueued_jobs
    end

    test "enqueues SyncRecentEventsJob for each provided body name" do
      bodies = [ "City Council", "Planning Commission", "Arts Commission" ]

      assert_enqueued_jobs 3, only: Ingestion::SyncRecentEventsJob do
        SyncRecentEventsForAllBodiesJob.new.perform(limit: 5, body_names: bodies)
      end
    end

    test "forwards the limit and body name to each enqueued SyncRecentEventsJob" do
      SyncRecentEventsForAllBodiesJob.new.perform(
        limit: 25,
        body_names: [ "City Council" ]
      )

      job = enqueued_jobs.find { |j| j["job_class"] == "Ingestion::SyncRecentEventsJob" }
      assert_not_nil job

      kwargs = job.fetch("arguments").last
      assert_equal 25, kwargs["limit"]
      assert_equal "City Council", kwargs["body_name"]
    end

    test "no per-body jobs are enqueued when the body list is empty" do
      assert_enqueued_jobs 0, only: Ingestion::SyncRecentEventsJob do
        SyncRecentEventsForAllBodiesJob.new.perform(limit: 10, body_names: [])
      end
    end

    test "delegates to Legistar::Client#bodies when body_names is nil" do
      fake_bodies = [
        { "BodyActiveFlag" => 1, "BodyName" => "City Council" },
        { "BodyActiveFlag" => 1, "BodyName" => "Planning Commission" },
        { "BodyActiveFlag" => 0, "BodyName" => "InactiveZoningBoard" }
      ]

      fake_client = Object.new
      fake_client.define_singleton_method(:bodies) { { status: 200, payload: fake_bodies } }

      original_new = Legistar::Client.method(:new)
      Legistar::Client.define_singleton_method(:new) { |**| fake_client }

      assert_enqueued_jobs 2, only: Ingestion::SyncRecentEventsJob do
        SyncRecentEventsForAllBodiesJob.new.perform(limit: 10)
      end

      enqueued = enqueued_jobs.select { |j| j["job_class"] == "Ingestion::SyncRecentEventsJob" }
      body_names = enqueued.map { |j| j["arguments"].last["body_name"] }.sort
      assert_equal [ "City Council", "Planning Commission" ], body_names
    ensure
      Legistar::Client.define_singleton_method(:new, original_new)
    end

    test "raises on non-200 status and uses cached bodies when available" do
      cache = ActiveSupport::Cache::MemoryStore.new
      cache.write(
        SyncRecentEventsForAllBodiesJob::CACHE_KEY,
        [ "Parks Commission" ],
        expires_in: SyncRecentEventsForAllBodiesJob::CACHE_TTL
      )

      fake_client = Object.new
      fake_client.define_singleton_method(:bodies) { { status: 503, payload: [] } }

      original_new = Legistar::Client.method(:new)
      Legistar::Client.define_singleton_method(:new) { |**| fake_client }

      log_stringio = StringIO.new
      old_logger = Rails.logger
      Rails.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(log_stringio))

      assert_enqueued_jobs 1, only: Ingestion::SyncRecentEventsJob do
        SyncRecentEventsForAllBodiesJob.new.perform(limit: 10, cache: cache)
      end
    ensure
      Legistar::Client.define_singleton_method(:new, original_new)
      Rails.logger = old_logger
      assert_match(/returned HTTP 503/, log_stringio.string)
      assert_match(/using 1 cached body names/, log_stringio.string)
    end

    test "propagates unexpected errors even when cache is available" do
      cache = ActiveSupport::Cache::MemoryStore.new
      cache.write(
        SyncRecentEventsForAllBodiesJob::CACHE_KEY,
        [ "City Council" ],
        expires_in: SyncRecentEventsForAllBodiesJob::CACHE_TTL
      )

      bad_payload = "not an array"
      bad_payload.define_singleton_method(:select) { raise NoMethodError, "undefined method `[]' for nil" }

      fake_client = Object.new
      fake_client.define_singleton_method(:bodies) { { status: 200, payload: bad_payload } }

      original_new = Legistar::Client.method(:new)
      Legistar::Client.define_singleton_method(:new) { |**| fake_client }

      assert_raises(NoMethodError) do
        SyncRecentEventsForAllBodiesJob.new.perform(limit: 10, cache: cache)
      end

      assert_enqueued_jobs 0
    ensure
      Legistar::Client.define_singleton_method(:new, original_new)
    end

    test "uses cached body names when live fetch fails" do
      cache = ActiveSupport::Cache::MemoryStore.new
      cache.write(
        SyncRecentEventsForAllBodiesJob::CACHE_KEY,
        [ "City Council", "Parks Commission" ],
        expires_in: SyncRecentEventsForAllBodiesJob::CACHE_TTL
      )

      failing_client = Object.new
      failing_client.define_singleton_method(:bodies) { raise Net::OpenTimeout, "execution expired" }

      original_new = Legistar::Client.method(:new)
      Legistar::Client.define_singleton_method(:new) { |**| failing_client }

      log_stringio = StringIO.new
      old_logger = Rails.logger
      Rails.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(log_stringio))

      assert_enqueued_jobs 2, only: Ingestion::SyncRecentEventsJob do
        SyncRecentEventsForAllBodiesJob.new.perform(limit: 5, cache: cache)
      end
    ensure
      Legistar::Client.define_singleton_method(:new, original_new)
      Rails.logger = old_logger
      assert_match(/using 2 cached body names/, log_stringio.string)
    end

    test "raises when live fetch fails and no cached body names exist" do
      failing_client = Object.new
      failing_client.define_singleton_method(:bodies) { raise Net::OpenTimeout, "execution expired" }

      original_new = Legistar::Client.method(:new)
      Legistar::Client.define_singleton_method(:new) { |**| failing_client }

      cache = ActiveSupport::Cache::MemoryStore.new

      assert_raises(Net::OpenTimeout) do
        SyncRecentEventsForAllBodiesJob.new.perform(limit: 5, cache: cache)
      end

      assert_enqueued_jobs 0
    ensure
      Legistar::Client.define_singleton_method(:new, original_new)
    end

    test "writes active body names to cache on successful fetch" do
      fake_bodies = [
        { "BodyActiveFlag" => 1, "BodyName" => "City Council" },
        { "BodyActiveFlag" => 1, "BodyName" => "Planning Commission" }
      ]

      fake_client = Object.new
      fake_client.define_singleton_method(:bodies) { { status: 200, payload: fake_bodies } }

      original_new = Legistar::Client.method(:new)
      Legistar::Client.define_singleton_method(:new) { |**| fake_client }

      cache = ActiveSupport::Cache::MemoryStore.new

      SyncRecentEventsForAllBodiesJob.new.perform(limit: 10, cache: cache)

      cached = cache.read(SyncRecentEventsForAllBodiesJob::CACHE_KEY)
      assert_equal [ "City Council", "Planning Commission" ], cached
    ensure
      Legistar::Client.define_singleton_method(:new, original_new)
    end
  end
end

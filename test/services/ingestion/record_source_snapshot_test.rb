require "test_helper"

module Ingestion
  class RecordSourceSnapshotTest < ActiveSupport::TestCase
    test "creates a new snapshot row when none exists for the identity" do
      assert_difference -> { SourceSnapshot.count }, 1 do
        snapshot = RecordSourceSnapshot.call(
          source_system: "legistar.sanjose",
          resource_type: "event",
          source_id: "7621",
          request_url: "https://example.test/Events/7621",
          fetched_at: Time.zone.parse("2026-05-15 10:00:00"),
          http_status: 200,
          response_sha256: "sha-v1",
          payload: { "EventId" => 7621 }
        )

        assert_equal 1, snapshot.fetch_count
        assert_equal Time.zone.parse("2026-05-15 10:00:00"), snapshot.fetched_at
        assert_equal Time.zone.parse("2026-05-15 10:00:00"), snapshot.last_fetched_at
      end
    end

    test "increments fetch_count instead of inserting when the response sha matches" do
      first = RecordSourceSnapshot.call(
        source_system: "legistar.sanjose",
        resource_type: "event",
        source_id: "7621",
        request_url: "https://example.test/Events/7621",
        fetched_at: Time.zone.parse("2026-05-15 10:00:00"),
        http_status: 200,
        response_sha256: "sha-v1",
        payload: { "EventId" => 7621 }
      )

      assert_no_difference -> { SourceSnapshot.count } do
        second = RecordSourceSnapshot.call(
          source_system: "legistar.sanjose",
          resource_type: "event",
          source_id: "7621",
          request_url: "https://example.test/Events/7621",
          fetched_at: Time.zone.parse("2026-05-15 11:30:00"),
          http_status: 200,
          response_sha256: "sha-v1",
          payload: { "EventId" => 7621 }
        )

        assert_equal first.id, second.id
        assert_equal 2, second.fetch_count
        assert_equal Time.zone.parse("2026-05-15 11:30:00"), second.last_fetched_at
        assert_equal Time.zone.parse("2026-05-15 10:00:00"), second.fetched_at, "first-seen timestamp should be preserved"
      end
    end

    test "uses update path for an existing response sha instead of logging a uniqueness violation" do
      RecordSourceSnapshot.call(
        source_system: "legistar.sanjose",
        resource_type: "event",
        source_id: "7621",
        request_url: "https://example.test/Events/7621",
        fetched_at: Time.zone.parse("2026-05-15 10:00:00"),
        http_status: 200,
        response_sha256: "sha-v1",
        payload: { "EventId" => 7621 }
      )

      insert_count = 0
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        insert_count += 1 if payload[:sql].include?('INSERT INTO "ingestion_source_snapshots"')
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        RecordSourceSnapshot.call(
          source_system: "legistar.sanjose",
          resource_type: "event",
          source_id: "7621",
          request_url: "https://example.test/Events/7621",
          fetched_at: Time.zone.parse("2026-05-15 11:30:00"),
          http_status: 200,
          response_sha256: "sha-v1",
          payload: { "EventId" => 7621 }
        )
      end

      assert_equal 0, insert_count
    end

    test "deduplicates by payload version even after another version has been observed" do
      first = RecordSourceSnapshot.call(
        source_system: "legistar.sanjose",
        resource_type: "event",
        source_id: "7621",
        request_url: "https://example.test/Events/7621",
        fetched_at: Time.zone.parse("2026-05-15 10:00:00"),
        http_status: 200,
        response_sha256: "sha-v1",
        payload: { "EventId" => 7621, "EventTitle" => "Original" }
      )

      RecordSourceSnapshot.call(
        source_system: "legistar.sanjose",
        resource_type: "event",
        source_id: "7621",
        request_url: "https://example.test/Events/7621",
        fetched_at: Time.zone.parse("2026-05-15 11:00:00"),
        http_status: 200,
        response_sha256: "sha-v2",
        payload: { "EventId" => 7621, "EventTitle" => "Changed" }
      )

      assert_no_difference -> { SourceSnapshot.count } do
        observed_again = RecordSourceSnapshot.call(
          source_system: "legistar.sanjose",
          resource_type: "event",
          source_id: "7621",
          request_url: "https://example.test/Events/7621",
          fetched_at: Time.zone.parse("2026-05-15 12:00:00"),
          http_status: 200,
          response_sha256: "sha-v1",
          payload: { "EventId" => 7621, "EventTitle" => "Original" }
        )

        assert_equal first.id, observed_again.id
        assert_equal 2, observed_again.fetch_count
      end
    end

    test "inserts a new snapshot when the response sha changes" do
      RecordSourceSnapshot.call(
        source_system: "legistar.sanjose",
        resource_type: "event",
        source_id: "7621",
        request_url: "https://example.test/Events/7621",
        fetched_at: Time.zone.parse("2026-05-15 10:00:00"),
        http_status: 200,
        response_sha256: "sha-v1",
        payload: { "EventId" => 7621, "EventTitle" => "Original" }
      )

      assert_difference -> { SourceSnapshot.count }, 1 do
        snapshot = RecordSourceSnapshot.call(
          source_system: "legistar.sanjose",
          resource_type: "event",
          source_id: "7621",
          request_url: "https://example.test/Events/7621",
          fetched_at: Time.zone.parse("2026-05-15 12:00:00"),
          http_status: 200,
          response_sha256: "sha-v2",
          payload: { "EventId" => 7621, "EventTitle" => "Renamed" }
        )

        assert_equal 1, snapshot.fetch_count
        assert_equal "sha-v2", snapshot.response_sha256
      end
    end

    test "does not collide across different source systems with the same source_id" do
      RecordSourceSnapshot.call(
        source_system: "legistar.sanjose",
        resource_type: "event",
        source_id: "7621",
        request_url: "https://example.test/Events/7621",
        fetched_at: Time.current,
        http_status: 200,
        response_sha256: "shared-sha",
        payload: { "EventId" => 7621 }
      )

      assert_difference -> { SourceSnapshot.count }, 1 do
        RecordSourceSnapshot.call(
          source_system: "legistar.santaclara",
          resource_type: "event",
          source_id: "7621",
          request_url: "https://example.test/Events/7621",
          fetched_at: Time.current,
          http_status: 200,
          response_sha256: "shared-sha",
          payload: { "EventId" => 7621 }
        )
      end
    end
  end
end

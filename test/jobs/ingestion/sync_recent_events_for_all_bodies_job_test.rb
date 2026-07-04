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

    test "raises HttpServerError (transient) when /Bodies returns 5xx" do
      stub_bodies_response(status: 503, body: "[]") do
        assert_raises(Legistar::Client::HttpServerError) do
          SyncRecentEventsForAllBodiesJob.new.perform(limit: 10, body_names: nil)
        end
      end
    end

    test "raises HttpClientError (permanent) when /Bodies returns 4xx" do
      stub_bodies_response(status: 404, body: "[]") do
        assert_raises(Legistar::Client::HttpClientError) do
          SyncRecentEventsForAllBodiesJob.new.perform(limit: 10, body_names: nil)
        end
      end
    end

    private

    def stub_bodies_response(status:, body:)
      response = Object.new
      response.define_singleton_method(:code) { status.to_s }
      response.define_singleton_method(:body) { body }
      original = Net::HTTP.method(:get_response)
      Net::HTTP.define_singleton_method(:get_response) do |*_args|
        response
      end
      yield
    ensure
      Net::HTTP.define_singleton_method(:get_response, original)
    end
  end
end

require "test_helper"

module DataHealth
  class JobStatusSnapshotTest < ActiveSupport::TestCase
    test "level is green when no failures in last hour" do
      snapshot = DataHealth::JobStatusSnapshot.create!(
        failed_jobs_last_hour: 0,
        failed_jobs_last_24_hours: 3
      )
      assert_equal :green, snapshot.level
    end

    test "level is amber for 1-5 failures in last hour" do
      [ 1, 3, 5 ].each do |count|
        snapshot = DataHealth::JobStatusSnapshot.create!(
          failed_jobs_last_hour: count,
          failed_jobs_last_24_hours: count
        )
        assert_equal :amber, snapshot.level, "expected :amber for #{count} failures"
      end
    end

    test "level is red for more than 5 failures in last hour" do
      [ 6, 10, 100 ].each do |count|
        snapshot = DataHealth::JobStatusSnapshot.create!(
          failed_jobs_last_hour: count,
          failed_jobs_last_24_hours: count
        )
        assert_equal :red, snapshot.level, "expected :red for #{count} failures"
      end
    end
  end
end

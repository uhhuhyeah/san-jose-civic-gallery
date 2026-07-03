require "test_helper"

class DataHealth::SnapshotTest < ActiveSupport::TestCase
  setup do
    @jurisdiction = Civic::Jurisdiction.create!(slug: "test-jur", name: "Test", ingestion_source_label: "Test Source")
    @snapshot = DataHealth::Snapshot.new(jurisdiction: @jurisdiction)
  end

  test "failed_job_count returns SolidQueue count" do
    # Stub count method to return a known value
    SolidQueue::FailedExecution.stub(:count, 7) do
      assert_equal 7, @snapshot.failed_job_count
    end
  end
end

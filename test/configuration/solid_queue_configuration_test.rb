require "test_helper"

class SolidQueueConfigurationTest < ActiveSupport::TestCase
  test "production workers cover each application queue" do
    queue_config = load_yaml_config("config/queue.yml").fetch("production")

    queues = worker_queues(queue_config)

    assert_includes queues, "default"
    assert_includes queues, "solid_queue_recurring"
    assert_includes queues, "generated_summary"
    assert_includes queues, "slow_extract"
    assert_includes queues, "iqm2_ingestion"
  end

  test "recurring generated summaries enqueue a dedicated job instead of running inline" do
    recurring_config = load_yaml_config("config/recurring.yml").fetch("production")
    task = recurring_config.fetch("generate_attachment_summaries")

    assert_equal "Generated::BackfillAttachmentSummariesJob", task.fetch("class")
    assert_not task.key?("command"), "generated summaries should not run inside solid_queue_recurring"
  end

  test "recurring Santa Clara County discovery enqueues the IQM2 sync job" do
    recurring_config = load_yaml_config("config/recurring.yml").fetch("production")
    task = recurring_config.fetch("sync_recent_sccounty_meetings")

    assert_equal "Ingestion::Iqm2::SyncMeetingsJob", task.fetch("class")
    assert_not task.key?("command"), "county discovery should enqueue a job, not run inline"
  end

  private

  def load_yaml_config(path)
    YAML.safe_load_file(Rails.root.join(path), aliases: true)
  end

  def worker_queues(config)
    config.fetch("workers").flat_map { |worker| worker.fetch("queues") }.uniq
  end
end

require "test_helper"

class SolidQueueConfigurationTest < ActiveSupport::TestCase
  test "production workers cover each application queue" do
    queue_config = load_yaml_config("config/queue.yml").fetch("production")

    queues = worker_queues(queue_config)

    assert_includes queues, "default"
    assert_includes queues, "solid_queue_recurring"
    assert_includes queues, "generated_summary"
    assert_includes queues, "slow_extract"
  end

  test "recurring generated summaries enqueue a dedicated job instead of running inline" do
    recurring_config = load_yaml_config("config/recurring.yml").fetch("production")
    task = recurring_config.fetch("generate_attachment_summaries")

    assert_equal "Generated::BackfillAttachmentSummariesJob", task.fetch("class")
    assert_not task.key?("command"), "generated summaries should not run inside solid_queue_recurring"
  end

  private

  def load_yaml_config(path)
    YAML.safe_load_file(Rails.root.join(path), aliases: true)
  end

  def worker_queues(config)
    config.fetch("workers").flat_map { |worker| worker.fetch("queues") }.uniq
  end
end

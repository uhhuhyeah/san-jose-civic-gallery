require "test_helper"

class SolidQueueConfigurationTest < ActiveSupport::TestCase
  test "production workers process recurring command jobs" do
    queue_config = load_yaml_config("config/queue.yml").fetch("production")
    recurring_config = load_yaml_config("config/recurring.yml").fetch("production")

    command_tasks = recurring_config.values.select { |task| task.key?("command") }

    assert command_tasks.any?, "expected at least one recurring command task"
    assert_includes worker_queues(queue_config), "solid_queue_recurring"
  end

  private

  def load_yaml_config(path)
    YAML.safe_load_file(Rails.root.join(path), aliases: true)
  end

  def worker_queues(config)
    config.fetch("workers").flat_map { |worker| worker.fetch("queues") }.uniq
  end
end

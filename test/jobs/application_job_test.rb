require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  test "discards on ActiveJob::DeserializationError" do
    job = Class.new(ApplicationJob) do
      def perform
        raise StandardError, "original cause"
      rescue StandardError
        raise ActiveJob::DeserializationError
      end
    end

    assert_nothing_raised do
      job.perform_now
    end
  end

  test "retries on Net::ReadTimeout" do
    job = Class.new(ApplicationJob) do
      def perform
        raise Net::ReadTimeout
      end
    end

    assert_enqueued_jobs 1 do
      job.perform_now
    end
  end

  test "retries on Errno::ECONNRESET" do
    job = Class.new(ApplicationJob) do
      def perform
        raise Errno::ECONNRESET
      end
    end

    assert_enqueued_jobs 1 do
      job.perform_now
    end
  end

  test "retries on SocketError" do
    job = Class.new(ApplicationJob) do
      def perform
        raise SocketError
      end
    end

    assert_enqueued_jobs 1 do
      job.perform_now
    end
  end

  test "does not retry on unrelated StandardError" do
    job = Class.new(ApplicationJob) do
      def perform
        raise ArgumentError, "unrelated error"
      end
    end

    assert_raises(ArgumentError) do
      job.perform_now
    end
  end
end

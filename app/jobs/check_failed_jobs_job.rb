class CheckFailedJobsJob < ApplicationJob
  queue_as :background

  # Periodically check for failed SolidQueue executions and surface the count
  # via Sentry so operators can act before jobs pile up.
  def perform
    count = SolidQueue::FailedExecution.count
    return if count.zero?

    # Capture a short message; include stack trace to aid debugging.
    Sentry.capture_message(
      "SolidQueue has #{count} failed job#{'s' if count != 1}." +
        " Run `solid_queue:failed` for details."
    )
  end
end

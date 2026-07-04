module DataHealth
  # Point-in-time snapshot of Solid Queue failed-job counts. Populated
  # by the recurring JobHealthCheckJob; used for alerting thresholds
  # and trend analysis on the /data page and in monitoring dashboards.
  class JobStatusSnapshot < ApplicationRecord
    self.table_name = "data_health_job_status_snapshots"

    def level
      if failed_jobs_last_hour.zero?
        :green
      elsif failed_jobs_last_hour <= 5
        :amber
      else
        :red
      end
    end
  end
end

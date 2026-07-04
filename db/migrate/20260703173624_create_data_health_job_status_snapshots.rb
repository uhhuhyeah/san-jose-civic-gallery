class CreateDataHealthJobStatusSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :data_health_job_status_snapshots do |t|
      t.integer :failed_jobs_last_hour, null: false, default: 0
      t.integer :failed_jobs_last_24_hours, null: false, default: 0
      t.datetime :captured_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.index :captured_at
    end
  end
end

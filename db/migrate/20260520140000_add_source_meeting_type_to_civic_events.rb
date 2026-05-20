class AddSourceMeetingTypeToCivicEvents < ActiveRecord::Migration[8.1]
  def change
    # Simbli exposes a meeting type/category (e.g. "Regular Session Board
    # Meeting") with no clean governing-body field. We store it here and keep
    # body_name as the deliberate jurisdiction body. Null for Legistar rows.
    add_column :civic_events, :source_meeting_type, :string
  end
end

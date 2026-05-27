module Civic
  class RoundupPeriod < ApplicationRecord
    self.table_name = "civic_roundup_periods"

    belongs_to :civic_jurisdiction, class_name: "Civic::Jurisdiction"

    validates :period_start, presence: true
    validates :period_end, presence: true
    validates :label, presence: true
    validates :period_start, uniqueness: { scope: [ :civic_jurisdiction_id, :period_end ] }

    scope :for_jurisdiction, ->(jurisdiction) { where(civic_jurisdiction: jurisdiction) }
    scope :recent_first, -> { order(period_start: :desc) }

    def self.for_month(jurisdiction:, year:, month:)
      period_start = Date.new(year, month, 1)
      period_end = period_start.end_of_month
      label = period_start.strftime("%B %Y")

      find_or_create_by!(
        civic_jurisdiction: jurisdiction,
        period_start: period_start,
        period_end: period_end
      ) do |record|
        record.label = label
      end
    end

    def to_param
      period_start.strftime("%Y-%m")
    end
  end
end

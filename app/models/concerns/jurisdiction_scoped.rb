# Mixed into civic records (events, event items, matters, attachments) to give
# them a jurisdiction. Jurisdiction is 1:1 with source_system for now, so a
# record with no explicit jurisdiction derives one from its source_system. This
# keeps existing San Jose code (which never sets a jurisdiction) working
# unchanged while making the column safe to require.
module JurisdictionScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :civic_jurisdiction, class_name: "Civic::Jurisdiction"

    before_validation :assign_default_jurisdiction

    scope :for_jurisdiction, ->(jurisdiction) { where(civic_jurisdiction: jurisdiction) }
  end

  private

  def assign_default_jurisdiction
    self.civic_jurisdiction ||= Civic::Jurisdiction.for_source_system(source_system)
  end
end

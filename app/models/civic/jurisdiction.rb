module Civic
  class Jurisdiction < ApplicationRecord
    self.table_name = "civic_jurisdictions"

    KINDS = %w[city school_district county special_district].freeze

    # Canonical jurisdictions. Kept idempotent so seeds.rb and fresh
    # (schema-loaded) databases converge on the same rows. The first
    # SJUSD-introducing migration freezes its own copy of these values.
    DEFAULTS = [
      {
        slug: "sanjose",
        name: "San Jose City Government",
        kind: "city",
        primary_host: "sanjose.civicgallery.org",
        source_system_default: "legistar.sanjose"
      },
      {
        slug: "sjusd",
        name: "San Jose Unified School District",
        kind: "school_district",
        primary_host: "sjusd.civicgallery.org",
        source_system_default: "simbli.sjusd"
      }
    ].freeze

    has_many :events, class_name: "Civic::Event", foreign_key: :civic_jurisdiction_id, inverse_of: :civic_jurisdiction, dependent: :restrict_with_exception
    has_many :event_items, class_name: "Civic::EventItem", foreign_key: :civic_jurisdiction_id, inverse_of: :civic_jurisdiction, dependent: :restrict_with_exception
    has_many :matters, class_name: "Civic::Matter", foreign_key: :civic_jurisdiction_id, inverse_of: :civic_jurisdiction, dependent: :restrict_with_exception
    has_many :matter_attachments, class_name: "Civic::MatterAttachment", foreign_key: :civic_jurisdiction_id, inverse_of: :civic_jurisdiction, dependent: :restrict_with_exception

    validates :slug, presence: true, uniqueness: true
    validates :name, presence: true
    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :primary_host, presence: true, uniqueness: true
    validates :source_system_default, uniqueness: true, allow_nil: true

    def self.for_source_system(source_system)
      return if source_system.blank?

      find_by(source_system_default: source_system)
    end

    def self.default
      find_by(slug: "sanjose")
    end

    def self.seed_defaults!
      DEFAULTS.map do |attributes|
        record = find_or_initialize_by(slug: attributes[:slug])
        record.update!(attributes)
        record
      end
    end

    def to_param
      slug
    end
  end
end
